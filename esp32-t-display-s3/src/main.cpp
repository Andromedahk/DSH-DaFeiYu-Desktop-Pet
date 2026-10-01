#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <JPEGDEC.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <cmath>
#include <ctime>

// Standard, non-touch LILYGO T-Display-S3: ST7789, 8-bit parallel, 320x170 landscape.
static Arduino_DataBus *bus = new Arduino_ESP32PAR8Q(7, 6, 8, 9, 39, 40, 41, 42, 45, 46, 47, 48);
static Arduino_GFX *gfx = new Arduino_ST7789(bus, 5, 0, true, 170, 320, 35, 0, 35, 0);
static JPEGDEC jpeg;
static Preferences prefs;

#define ASSET(name) \
  extern const uint8_t name##_start[] asm("_binary_data_" #name "_start"); \
  extern const uint8_t name##_end[] asm("_binary_data_" #name "_end")
ASSET(deepseek_jpg);
ASSET(deepseek_offline_jpg);
ASSET(gpt_jpg);
ASSET(claude_jpg);
ASSET(gemini_jpg);
ASSET(x509_crt_bundle_bin);

struct ImageAsset { const uint8_t *start; const uint8_t *end; };
static const ImageAsset images[] = {
  {deepseek_jpg_start, deepseek_jpg_end}, {gpt_jpg_start, gpt_jpg_end},
  {claude_jpg_start, claude_jpg_end}, {gemini_jpg_start, gemini_jpg_end},
};
static const ImageAsset offlineImage = {deepseek_offline_jpg_start, deepseek_offline_jpg_end};
static const char *names[] = {"DeepSeek", "GPT", "Claude", "Gemini"};

enum class AuthMode : uint8_t { None, ApiKey, Account };
enum class LinkState : uint8_t { NeedWifi, NeedKey, Connecting, Ready, Error, RateLimited };
static AuthMode authMode = AuthMode::None;
static LinkState linkState = LinkState::NeedWifi;
static String ssid, password, token, issuer, errorText;
static uint8_t character = 0;
static uint32_t pollIntervalMs = 30000;
static uint32_t nextPoll = 0, retryNotBefore = 0, backoffMs = 30000;
static uint32_t lastAnimation = 0, lastWifiTry = 0;
static int64_t shownCents = 0, targetCents = 0;
static bool hasBalance = false, isAnimating = false, needsDraw = true;
static String serialLine;
static int lastScrollPage = -1;

static bool reached(uint32_t deadline) { return int32_t(millis() - deadline) >= 0; }

static bool validSingleLine(const String &value, size_t limit) {
  if (value.isEmpty() || value.length() > limit) return false;
  for (size_t i = 0; i < value.length(); ++i) {
    const uint8_t c = static_cast<uint8_t>(value[i]);
    if (c < 33 || c > 126) return false;
  }
  return true;
}

static bool validIssuer(const String &value) {
  if (!value.startsWith("https://") || value.length() > 256) return false;
  String tail = value.substring(8);
  if (tail.isEmpty() || tail.indexOf('@') >= 0 || tail.indexOf('?') >= 0 ||
      tail.indexOf('#') >= 0 || tail.indexOf('\\') >= 0 || tail.indexOf('%') >= 0) return false;
  for (size_t i = 0; i < tail.length(); ++i) {
    if (tail[i] <= ' ' || tail[i] == 127) return false;
  }
  const int slash = tail.indexOf('/');
  String host = slash < 0 ? tail : tail.substring(0, slash);
  return !host.isEmpty() && host.indexOf(':') < 0;
}

static int jpegDraw(JPEGDRAW *draw) {
  gfx->draw16bitRGBBitmap(draw->x, draw->y, draw->pPixels, draw->iWidth, draw->iHeight);
  return 1;
}

static void drawImage(const ImageAsset &asset) {
  const int length = int(asset.end - asset.start);
  if (jpeg.openFLASH(const_cast<uint8_t *>(asset.start), length, jpegDraw)) {
    jpeg.setPixelType(RGB565_LITTLE_ENDIAN);
    jpeg.decode(0, 0, 0);
    jpeg.close();
  }
}

static String money(int64_t cents) {
  const bool negative = cents < 0;
  const uint64_t absCents = negative ? uint64_t(-(cents + 1)) + 1 : uint64_t(cents);
  char buffer[36];
  snprintf(buffer, sizeof(buffer), "%s%llu.%02llu", negative ? "-" : "",
           static_cast<unsigned long long>(absCents / 100),
           static_cast<unsigned long long>(absCents % 100));
  return String(buffer);
}

static void drawScreen() {
  const bool offline = character == 0 && linkState != LinkState::Ready;
  drawImage(offline ? offlineImage : images[character]);
  if (hasBalance && linkState == LinkState::Ready) {
    // The tablet's safe inner region scales from the macOS 1536x1024 artwork
    // to the 255x170 image centred on this 320x170 display.
    const String amount = money(shownCents);
    const int maxChars = 8;
    const int pages = max(1, int(amount.length()) - maxChars + 1);
    const int page = pages == 1 ? 0 : (millis() / 800) % pages;
    const String visible = amount.substring(page, page + maxChars);
    const int width = visible.length() * 6;
    gfx->setTextWrap(false);
    gfx->setTextColor(isAnimating ? RED : WHITE);
    gfx->setTextSize(1);
    gfx->setCursor(241 - width / 2, 126);
    gfx->print(visible);
    lastScrollPage = page;
  } else lastScrollPage = -1;
  needsDraw = false;
}

static bool decimalValue(JsonVariantConst value, long double &result) {
  if (value.isNull() || value.is<bool>()) return false;
  String text;
  if (value.is<const char *>()) text = value.as<const char *>();
  else serializeJson(value, text);
  if (text.isEmpty() || text.length() > 48) return false;
  const char *first = text.c_str();
  char *end = nullptr;
  result = strtold(first, &end);
  return end != first && *end == '\0' && std::isfinite(static_cast<double>(result));
}

static bool successCode(JsonVariantConst value) {
  long double code = 0;
  return decimalValue(value, code) && code == 0;
}

static bool sumWallets(JsonVariantConst value, const char *amountKey, bool required,
                       long double &sum, bool &foundCny) {
  if (value.isNull()) return !required;
  if (!value.is<JsonArrayConst>()) return false;
  for (JsonObjectConst wallet : value.as<JsonArrayConst>()) {
    const char *currency = wallet["currency"];
    if (!currency) return false;
    if (strcmp(currency, "CNY") != 0) continue;
    long double amount = 0;
    if (!decimalValue(wallet[amountKey], amount)) return false;
    sum += amount;
    if (!std::isfinite(static_cast<double>(sum))) return false;
    foundCny = true;
  }
  return true;
}

static bool parseBalance(const String &body, int64_t &cents) {
  DynamicJsonDocument doc(32768);
  if (deserializeJson(doc, body)) return false;
  JsonVariantConst root = doc.as<JsonVariantConst>();
  if (!root.is<JsonObjectConst>()) return false;
  JsonVariantConst wallets;
  JsonVariantConst bonuses;
  if (authMode == AuthMode::ApiKey) {
    wallets = root["balance_infos"];
  } else {
    JsonVariantConst payload = root;
    if (!root["code"].isNull() || !root["data"].isNull()) {
      if (!successCode(root["code"]) || !root["data"].is<JsonObjectConst>()) return false;
      payload = root["data"];
    }
    if (!payload["biz_code"].isNull() || !payload["biz_data"].isNull()) {
      if (!successCode(payload["biz_code"]) || !payload["biz_data"].is<JsonObjectConst>()) return false;
      payload = payload["biz_data"];
    }
    wallets = payload["normal_wallets"];
    bonuses = payload["bonus_wallets"];
  }
  long double total = 0;
  bool foundCny = false;
  if (!sumWallets(wallets, authMode == AuthMode::ApiKey ? "total_balance" : "balance",
                  true, total, foundCny)) return false;
  if (authMode == AuthMode::Account && !sumWallets(bonuses, "balance", false, total, foundCny)) return false;
  if (!foundCny || !std::isfinite(static_cast<double>(total))) return false;
  const long double scaled = total * 100.0L;
  if (fabsl(scaled) > 9000000000000000.0L) return false;
  cents = llroundl(scaled);
  return true;
}

static void acceptBalance(int64_t cents) {
  if (!hasBalance) {
    shownCents = targetCents = cents;
  } else if (cents > shownCents || shownCents - cents > 400) {
    shownCents = targetCents = cents;
    isAnimating = false;
  } else {
    targetCents = cents;
    isAnimating = shownCents > targetCents;
  }
  hasBalance = true;
  linkState = LinkState::Ready;
  errorText = "";
  needsDraw = true;
}

static void fetchBalance() {
  if (WiFi.status() != WL_CONNECTED || authMode == AuthMode::None) return;
  linkState = LinkState::Connecting;
  needsDraw = true;
  const String url = authMode == AuthMode::ApiKey
      ? String("https://api.deepseek.com/user/balance")
      : issuer + "/api/v0/users/get_user_summary";
  WiFiClientSecure client;
  client.setCACertBundle(x509_crt_bundle_bin_start);
  client.setTimeout(20);
  HTTPClient http;
  http.setTimeout(20000);
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  const char *headerKeys[] = {"Retry-After"};
  http.collectHeaders(headerKeys, 1);
  bool success = false;
  int response = -1;
  uint32_t waitMs = 0;
  if (http.begin(client, url)) {
    http.addHeader("Accept", "application/json");
    if (authMode == AuthMode::ApiKey) http.addHeader("Authorization", "Bearer " + token);
    else http.addHeader("x-dsh-auth-token", token);
    response = http.GET();
    if (response == 200) {
      const int size = http.getSize();
      if (size >= 0 && size > 32768) errorText = "Response too large";
      else {
        String body = http.getString();
        int64_t cents = 0;
        if (body.length() <= 32768 && parseBalance(body, cents)) {
          acceptBalance(cents);
          success = true;
        } else errorText = "Invalid balance data";
      }
    } else if (response == 429) {
      String retry = http.header("Retry-After");
      retry.trim();
      bool digits = !retry.isEmpty();
      for (size_t i = 0; i < retry.length(); ++i) digits &= isDigit(retry[i]);
      if (digits) {
        const uint64_t seconds = strtoull(retry.c_str(), nullptr, 10);
        waitMs = uint32_t(min<uint64_t>(86400000ULL, min<uint64_t>(86400ULL, seconds) * 1000ULL));
      }
      else waitMs = min<uint32_t>(300000, max<uint32_t>(pollIntervalMs, backoffMs * 2));
      backoffMs = waitMs;
      linkState = LinkState::RateLimited;
      errorText = "Rate limited";
    } else {
      errorText = response == 401 || response == 403 ? "Authentication failed" : "HTTPS request failed";
    }
    http.end();
  } else errorText = "HTTPS setup failed";
  if (!success && response != 429) linkState = LinkState::Error;
  const uint32_t now = millis();
  retryNotBefore = response == 429 ? now + waitMs : 0;
  nextPoll = response == 429 ? retryNotBefore : now + pollIntervalMs;
  if (response != 429) backoffMs = pollIntervalMs;
  needsDraw = true;
  Serial.printf("Balance request: HTTP %d, %s\n", response, success ? "OK" : errorText.c_str());
}

static void saveCredentials() {
  prefs.putString("ssid", ssid);
  prefs.putString("pass", password);
  prefs.putString("token", token);
  prefs.putString("issuer", issuer);
  prefs.putUChar("auth", static_cast<uint8_t>(authMode));
}

static void handleCommand(String line) {
  line.trim();
  if (line == "help") {
    Serial.println("wifi SSID|PASSWORD  /  api API_KEY  /  account HTTPS_ISSUER|TOKEN");
    Serial.println("next / refresh / interval SECONDS / status / clear");
  } else if (line.startsWith("wifi ")) {
    String value = line.substring(5);
    const int sep = value.indexOf('|');
    if (sep <= 0 || sep >= int(value.length()) - 1) { Serial.println("Invalid Wi-Fi input"); return; }
    String newSsid = value.substring(0, sep);
    String newPassword = value.substring(sep + 1);
    if (newSsid.length() > 32 || newPassword.length() > 64) { Serial.println("Wi-Fi input too long"); return; }
    ssid = newSsid; password = newPassword;
    saveCredentials();
    WiFi.disconnect();
    WiFi.begin(ssid.c_str(), password.c_str());
    linkState = LinkState::Connecting;
    nextPoll = millis();
    Serial.println("Wi-Fi saved; connecting");
  } else if (line.startsWith("api ")) {
    String value = line.substring(4); value.trim();
    if (!validSingleLine(value, 4096)) { Serial.println("Invalid API key"); return; }
    token = value; issuer = ""; authMode = AuthMode::ApiKey;
    saveCredentials(); retryNotBefore = 0; backoffMs = pollIntervalMs; nextPoll = millis();
    Serial.println("API key saved");
  } else if (line.startsWith("account ")) {
    String value = line.substring(8);
    const int sep = value.indexOf('|');
    if (sep < 0) { Serial.println("Invalid account input"); return; }
    String endpoint = value.substring(0, sep), key = value.substring(sep + 1);
    while (endpoint.endsWith("/")) endpoint.remove(endpoint.length() - 1);
    if (!validIssuer(endpoint) || !validSingleLine(key, 4096)) {
      Serial.println("Invalid account issuer or token"); return;
    }
    issuer = endpoint; token = key; authMode = AuthMode::Account;
    saveCredentials(); retryNotBefore = 0; backoffMs = pollIntervalMs; nextPoll = millis();
    Serial.println("Account credential saved");
  } else if (line == "clear") {
    prefs.clear(); ssid = password = token = issuer = "";
    authMode = AuthMode::None; hasBalance = false;
    WiFi.disconnect(true); linkState = LinkState::NeedWifi;
    Serial.println("Stored Wi-Fi and credentials cleared");
  } else if (line == "next") {
    character = (character + 1) % 4; prefs.putUChar("character", character);
  } else if (line == "refresh") {
    if (reached(retryNotBefore)) nextPoll = millis();
    else Serial.println("Waiting for rate limit");
  } else if (line.startsWith("interval ")) {
    const int seconds = line.substring(9).toInt();
    if (seconds < 10 || seconds > 300) { Serial.println("Use 10..300 seconds"); return; }
    pollIntervalMs = uint32_t(seconds) * 1000;
    prefs.putUInt("interval", pollIntervalMs);
    nextPoll = millis() + pollIntervalMs;
  } else if (line == "status") {
    Serial.printf("Wi-Fi: %s; auth: %s; character: %s; balance: %s\n",
                  WiFi.status() == WL_CONNECTED ? "connected" : "disconnected",
                  authMode == AuthMode::None ? "none" : authMode == AuthMode::ApiKey ? "API" : "account",
                  names[character], hasBalance ? money(shownCents).c_str() : "unknown");
  } else if (!line.isEmpty()) Serial.println("Unknown command. Type help.");
  needsDraw = true;
}

static void readSerial() {
  while (Serial.available()) {
    const char c = Serial.read();
    if (c == '\r' || c == '\n') {
      if (!serialLine.isEmpty()) handleCommand(serialLine);
      serialLine = "";
    } else if (serialLine.length() < 4500) serialLine += c;
    else { serialLine = ""; Serial.println("Input too long"); }
  }
}

static void handleButtons() {
  static bool previous0 = true, previous14 = true;
  static uint32_t debounce0 = 0, debounce14 = 0;
  bool now0 = digitalRead(0), now14 = digitalRead(14);
  if (previous0 && !now0 && millis() - debounce0 > 250) {
    character = (character + 1) % 4;
    prefs.putUChar("character", character);
    needsDraw = true;
    debounce0 = millis();
  }
  if (previous14 && !now14 && millis() - debounce14 > 250 && reached(retryNotBefore)) {
    nextPoll = millis();
    debounce14 = millis();
  }
  previous0 = now0; previous14 = now14;
}

void setup() {
  Serial.begin(115200);
  pinMode(15, OUTPUT); digitalWrite(15, HIGH);
  pinMode(38, OUTPUT); digitalWrite(38, HIGH);
  pinMode(0, INPUT_PULLUP); pinMode(14, INPUT_PULLUP);
  gfx->begin(); gfx->setRotation(1);
  prefs.begin("dshpet", false);
  ssid = prefs.getString("ssid"); password = prefs.getString("pass");
  token = prefs.getString("token"); issuer = prefs.getString("issuer");
  character = min<uint8_t>(3, prefs.getUChar("character", 0));
  pollIntervalMs = prefs.getUInt("interval", 30000);
  if (pollIntervalMs < 10000 || pollIntervalMs > 300000) pollIntervalMs = 30000;
  backoffMs = pollIntervalMs;
  const uint8_t mode = prefs.getUChar("auth", 0);
  authMode = mode == 1 && validSingleLine(token, 4096) ? AuthMode::ApiKey
      : mode == 2 && validSingleLine(token, 4096) && validIssuer(issuer) ? AuthMode::Account
      : AuthMode::None;
  linkState = ssid.isEmpty() ? LinkState::NeedWifi : authMode == AuthMode::None ? LinkState::NeedKey : LinkState::Connecting;
  WiFi.mode(WIFI_STA);
  if (!ssid.isEmpty()) WiFi.begin(ssid.c_str(), password.c_str());
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  drawScreen();
  Serial.println("DSH pet for T-Display-S3. Type help for setup commands.");
}

void loop() {
  readSerial();
  handleButtons();
  const uint32_t now = millis();
  if (ssid.isEmpty()) linkState = LinkState::NeedWifi;
  else if (WiFi.status() != WL_CONNECTED) {
    if (linkState != LinkState::Connecting) { linkState = LinkState::Connecting; needsDraw = true; }
    if (now - lastWifiTry >= 15000) {
      WiFi.begin(ssid.c_str(), password.c_str());
      lastWifiTry = now;
    }
  } else if (authMode == AuthMode::None) linkState = LinkState::NeedKey;
  else if (reached(nextPoll) && reached(retryNotBefore)) {
    // Certificate expiry checks need a trusted clock from NTP.
    if (time(nullptr) > 1700000000) fetchBalance();
  }
  if (isAnimating && now - lastAnimation >= 200) {
    --shownCents;
    isAnimating = shownCents > targetCents;
    lastAnimation = now;
    needsDraw = true;
#ifdef DSH_BUZZER_PIN
    tone(DSH_BUZZER_PIN, 880, 45);
#endif
  }
  if (hasBalance && linkState == LinkState::Ready) {
    const int pages = max(1, int(money(shownCents).length()) - 8 + 1);
    if (pages > 1 && int((now / 800) % pages) != lastScrollPage) needsDraw = true;
  }
  if (needsDraw) drawScreen();
  delay(10);
}
