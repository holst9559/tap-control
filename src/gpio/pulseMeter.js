const config = require('../config');

let Gpio = null;
let pigpioAvailable = false;

try {
  if (!config.mockGpio) {
    Gpio = require('pigpio').Gpio;
    pigpioAvailable = true;
  }
} catch (err) {
  pigpioAvailable = false;
  console.warn('[gpio] pigpio not available — using mock pulse meter:', err.message);
}

const meters = new Map();
const mockTimers = new Map();

function createMeterState(tapId, gpioPin, onPulse) {
  return {
    tapId,
    gpioPin,
    onPulse,
    gpio: null,
    pulseCount: 0,
  };
}

function handleFallingEdge(meter) {
  meter.pulseCount += 1;
  meter.onPulse(meter.tapId, meter.pulseCount);
}

function onMeterAlert(meter, level) {
  if (level === 0) {
    handleFallingEdge(meter);
  }
}

function attachPigpio(meter) {
  const gpio = new Gpio(meter.gpioPin, {
    mode: Gpio.INPUT,
    pullUpDown: Gpio.PUD_UP,
    alert: true,
  });

  gpio.glitchFilter(100);
  gpio.on('alert', onMeterAlert.bind(null, meter));
  meter.gpio = gpio;
}

function onMockBurst(meter) {
  for (let i = 0; i < 40; i += 1) {
    handleFallingEdge(meter);
  }
}

function startMockPulses(meter) {
  // Development helper: simulate a pour burst every 30s on tap 1 only when MOCK_AUTO=1
  if (process.env.MOCK_AUTO !== '1') {
    return;
  }

  if (meter.tapId !== 1) {
    return;
  }

  const timer = setInterval(onMockBurst, 30000, meter);
  mockTimers.set(meter.tapId, timer);
}

function startPulseMeters(taps, onPulse) {
  for (const tap of taps) {
    const meter = createMeterState(tap.id, tap.gpio_pin, onPulse);
    meters.set(tap.id, meter);

    if (pigpioAvailable) {
      attachPigpio(meter);
      console.log(`[gpio] tap ${tap.id} listening on BCM ${tap.gpio_pin}`);
    } else {
      console.log(`[gpio] tap ${tap.id} mock mode (BCM ${tap.gpio_pin})`);
      startMockPulses(meter);
    }
  }

  return {
    pigpioAvailable,
    injectPulse,
    getPulseCount,
    resetPulseCount,
    stopAll,
  };
}

function injectPulse(tapId) {
  const meter = meters.get(tapId);
  if (!meter) {
    return null;
  }
  handleFallingEdge(meter);
  return meter.pulseCount;
}

function getPulseCount(tapId) {
  const meter = meters.get(tapId);
  if (!meter) {
    return 0;
  }
  return meter.pulseCount;
}

function resetPulseCount(tapId) {
  const meter = meters.get(tapId);
  if (!meter) {
    return;
  }
  meter.pulseCount = 0;
}

function stopAll() {
  for (const meter of meters.values()) {
    if (meter.gpio) {
      meter.gpio.disableAlert();
    }
  }

  for (const timer of mockTimers.values()) {
    clearInterval(timer);
  }

  mockTimers.clear();
  meters.clear();
}

module.exports = {
  startPulseMeters,
  injectPulse,
  getPulseCount,
  resetPulseCount,
  stopAll,
};
