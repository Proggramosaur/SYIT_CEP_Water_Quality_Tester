// #include <Wire>
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
const long interval = 1000;   

String waterQuality;

void setup() 
{
  Serial.begin(115200);
  pinMode(pHsensor, INPUT);
  pinMode(turbiditySensor, INPUT);
  pinMode(tdsSensor, INPUT);
  
  Serial.println("=== Water Quality Monitor ===");
  Serial.println("pH | Turbidity (NTU) | TDS (ppm)");
  Serial.println("================================");
}

void loop()
{
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
    Serial.print("Water Status: ");
    Serial.println(waterQuality);
  }
}

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
  
  // Simple inverse linear mapping
  // 3.3V (clear water) = 0 NTU
  // 0V (very turbid) = 3000 NTU
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
  bool tdsSafe = (tdsValue <= 500);  // Changed: removed lower limit
  
  if(pHSafe && turbiditySafe && tdsSafe)
  {
    waterQuality = "SAFE TO DRINK";
  }
  else if(!pHSafe && !turbiditySafe && !tdsSafe)
  {
    waterQuality = "NOT DRINKABLE - Multiple Issues";
  }
  else if(!pHSafe)
  {
    if(phVal < 6.5)
      waterQuality = "NOT DRINKABLE - Too Acidic";
    else
      waterQuality = "NOT DRINKABLE - Too Alkaline";
  }
  else if(!turbiditySafe)
  {
    waterQuality = "NOT DRINKABLE - Too Cloudy";
  }
  else if(!tdsSafe)
  {
    waterQuality = "NOT DRINKABLE - High TDS";
  }
}