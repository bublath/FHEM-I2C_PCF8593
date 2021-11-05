# FHEM-I2C_PCF8593
Simple FHEM Module to drive PCF8593 counters (might also work with PCF8583) over I2C

Only supports Event Counter mode of the chip.
To use connect SDA,SCL,VCC and GDN(Vss) as normal.
Make sure to pull RESET to VCC in order for the device to work.
On OSCI you can now connect a device that submits pulses (e.g. flow meter) which will be counted by the device.
