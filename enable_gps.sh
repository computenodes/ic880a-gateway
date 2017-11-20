#!/bin/bash
GPS_EN_PIN="23"
GPS_RST_PIN="27"
echo "Enabling GPS module"
echo "$GPS_EN_PIN" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio$GPS_EN_PIN/direction
echo "1" > /sys/class/gpio/gpio$GPS_EN_PIN/value
echo "$GPS_RST_PIN" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio$GPS_RST_PIN/direction
echo "1" > /sys/class/gpio/gpio$GPS_RST_PIN/value

