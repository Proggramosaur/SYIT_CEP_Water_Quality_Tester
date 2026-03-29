#include <WiFi.h>
#include <PubSubClient.h>

// ================= WIFI =================
const char* ssid = "Wifi";
const char* password = "Password";

// ================= MQTT =================
const char* mqtt_server = "broker.hivemq.com";
const char* mqtt_topic = "water/device/data";

WiFiClient espClient;
PubSubClient client(espClient);

// ========== SENSOR PINS ==========
int pHsensor = 34;
int turbiditySensor = 35;
int tdsSensor = 32;

// ========== CALIBRATION VALUES ==========
float pH_calibration = 12.10;
float tds_calibration = 0.5;

// ========== pH VARIABLES ==========
unsigned long int avgval;
int buffer_arr[10], temp;
float phVal;

// ========== TURBIDITY VARIABLES ==========
float turbidityVoltage;
float turbidityNTU;

// ========== TDS VARIABLES ==========
float tdsVoltage;
float tdsValue;
const float VREF = 3.3;
const float ADC_RES = 4095.0;

// ========== TIMING ==========
unsigned long previousMillis = 0;
const long interval = 2000;

String waterQuality;

// ========== WIFI CONNECT ==========
void connectWiFi()
{
  Serial.println("Connecting WiFi...");
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi Connected!");
}

// ========== MQTT CONNECT ==========
void connectMQTT()
{
  while (!client.connected())
  {
    Serial.println("Connecting MQTT...");
    if (client.connect("ESP32_WATER_DEVICE"))
    {
      Serial.println("MQTT Connected!");
    }
    else
    {
      delay(2000);
    }
  }
}

void setup()
{
  Serial.begin(115200);

  pinMode(pHsensor, INPUT);
  pinMode(turbiditySensor, INPUT);
  pinMode(tdsSensor, INPUT);

  Serial.println("=== Water Quality Monitor ===");

  connectWiFi();
  client.setServer(mqtt_server, 1883);
}

void loop()
{
  if (!client.connected())
    connectMQTT();

  client.loop();

  readSensors();
}

void readSensors()
{
  unsigned long currentMillis = millis();

  if (currentMillis - previousMillis >= interval)
  {
    previousMillis = currentMillis;

    readPh();
    readTurbidity();
    readTDS();
    waterStatus();

    Serial.print("pH: ");
    Serial.print(phVal, 2);
    Serial.print(" | Turbidity: ");
    Serial.print(turbidityNTU, 2);
    Serial.print(" NTU | TDS: ");
    Serial.print(tdsValue, 0);
    Serial.println(" ppm");
    Serial.println("Status: " + waterQuality);

    // 🔥 Direct send — no checking
    sendMQTT();
  }
}

// ================= MQTT SEND =================
void sendMQTT()
{
  String payload = "{";
  payload += "\"ph\":" + String(phVal, 2) + ",";
  payload += "\"turbidity\":" + String(turbidityNTU, 2) + ",";
  payload += "\"tds\":" + String(tdsValue, 0) + ",";
  payload += "\"status\":\"" + waterQuality + "\"";
  payload += "}";

  client.publish(mqtt_topic, payload.c_str());

  Serial.println("Data sent via MQTT");
}

// ================= SENSOR FUNCTIONS =================

void readPh()
{
  for(int i = 0; i < 10; i++)
  {
    buffer_arr[i] = analogRead(pHsensor);
    delay(30);
  }

  for(int i = 0; i < 9; i++)
  {
    for(int j = i + 1; j < 10; j++)
    {
      if(buffer_arr[i] > buffer_arr[j])
      {
        temp = buffer_arr[i];
        buffer_arr[i] = buffer_arr[j];
        buffer_arr[j] = temp;
      }
    }
  }

  avgval = 0;
  for(int i = 2; i < 8; i++)
    avgval += buffer_arr[i];

  float volt = (avgval / 6.0) * VREF / ADC_RES;
  phVal = -4.90 * volt + pH_calibration;
}

void readTurbidity()
{
  int turbidityRaw = 0;

  for(int i = 0; i < 10; i++)
  {
    turbidityRaw += analogRead(turbiditySensor);
    delay(10);
  }

  turbidityRaw = turbidityRaw / 10;
  turbidityVoltage = turbidityRaw * (VREF / ADC_RES);
  turbidityNTU = (3.3 - turbidityVoltage) * 909.09;

  if(turbidityNTU < 0) turbidityNTU = 0;
  if(turbidityNTU > 3000) turbidityNTU = 3000;
}

void readTDS()
{
  int tdsRaw = 0;

  for(int i = 0; i < 10; i++)
  {
    tdsRaw += analogRead(tdsSensor);
    delay(10);
  }

  tdsRaw = tdsRaw / 10;
  tdsVoltage = tdsRaw * (VREF / ADC_RES);

  tdsValue = (133.42 * tdsVoltage * tdsVoltage * tdsVoltage
              - 255.86 * tdsVoltage * tdsVoltage
              + 857.39 * tdsVoltage) * tds_calibration;

  if(tdsValue < 0) tdsValue = 0;
}

void waterStatus()
{
  bool pHSafe = (phVal >= 6.5 && phVal <= 8.5);
  bool turbiditySafe = (turbidityNTU <= 5.0);
  bool tdsSafe = (tdsValue <= 500);

  if(pHSafe && turbiditySafe && tdsSafe)
    waterQuality = "SAFE TO DRINK";
  else if(!pHSafe && !turbiditySafe && !tdsSafe)
    waterQuality = "NOT DRINKABLE - Multiple Issues";
  else if(!pHSafe)
  {
    if(phVal < 6.5)
      waterQuality = "NOT DRINKABLE - Too Acidic";
    else
      waterQuality = "NOT DRINKABLE - Too Alkaline";
  }
  else if(!turbiditySafe)
    waterQuality = "NOT DRINKABLE - Too Cloudy";
  else if(!tdsSafe)
    waterQuality = "NOT DRINKABLE - High TDS";
}
