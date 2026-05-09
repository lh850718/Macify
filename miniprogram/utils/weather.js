const { getCache, setCache } = require('./storage.js');

const GEOCODE_URL = 'https://geocoding-api.open-meteo.com/v1/search';
const FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';
const FORECAST_TTL_MS = 30 * 60 * 1000;

function buildQuery(params) {
  return Object.keys(params)
    .map((key) => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
    .join('&');
}

function requestJson(url) {
  return new Promise((resolve, reject) => {
    wx.request({
      url,
      method: 'GET',
      success(response) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          resolve(response.data);
          return;
        }
        reject(new Error(`HTTP ${response.statusCode}`));
      },
      fail(error) {
        reject(error);
      },
    });
  });
}

function roundOrNull(value) {
  if (value === null || value === undefined || Number.isNaN(value)) return null;
  return Math.round(value);
}

function arrayItem(arr, index) {
  return Array.isArray(arr) ? arr[index] : null;
}

async function geocodeCity(city) {
  const key = String(city || '').trim().toLowerCase();
  if (!key) throw new Error('City is empty');

  const cache = getCache('geocode') || {};
  if (cache[key]) return cache[key];

  const query = buildQuery({
    name: city,
    count: 1,
    language: 'zh',
    format: 'json',
  });
  const data = await requestJson(`${GEOCODE_URL}?${query}`);
  const result = data && data.results && data.results[0];
  if (!result) throw new Error(`No geocode result for ${city}`);

  const entry = {
    lat: result.latitude,
    lng: result.longitude,
    name: result.name,
    country: result.country_code || '',
  };
  cache[key] = entry;
  setCache('geocode', cache);
  return entry;
}

function parseDaily(data) {
  const daily = data.daily || {};
  const times = Array.isArray(daily.time) ? daily.time : [];
  return times.map((date, index) => ({
    date,
    weatherCode: arrayItem(daily.weather_code, index),
    max: roundOrNull(arrayItem(daily.temperature_2m_max, index)),
    min: roundOrNull(arrayItem(daily.temperature_2m_min, index)),
    precipitation: roundOrNull(arrayItem(daily.precipitation_probability_max, index)),
    windSpeed: roundOrNull(arrayItem(daily.wind_speed_10m_max, index)),
  }));
}

async function fetchForecast(geo, tempUnit) {
  const query = buildQuery({
    latitude: geo.lat,
    longitude: geo.lng,
    current: 'temperature_2m,apparent_temperature,weather_code',
    daily: [
      'weather_code',
      'temperature_2m_max',
      'temperature_2m_min',
      'precipitation_probability_max',
      'wind_speed_10m_max',
    ].join(','),
    forecast_days: 3,
    temperature_unit: tempUnit === 'fahrenheit' ? 'fahrenheit' : 'celsius',
    wind_speed_unit: 'kmh',
    timezone: 'auto',
  });
  return requestJson(`${FORECAST_URL}?${query}`);
}

async function getForecast(options) {
  const city = String(options.city || '').trim();
  const tempUnit = options.tempUnit || 'celsius';
  const cacheKey = `${city.toLowerCase()}|${tempUnit}`;
  const cached = getCache('forecast');

  if (cached && cached.key === cacheKey && Date.now() - cached.ts < FORECAST_TTL_MS) {
    return cached.data;
  }

  const geo = await geocodeCity(city);
  const data = await fetchForecast(geo, tempUnit);
  const current = data.current || {};
  const forecast = {
    location: geo.name,
    unit: tempUnit === 'fahrenheit' ? 'F' : 'C',
    current: {
      temperature: roundOrNull(current.temperature_2m),
      feelsLike: roundOrNull(current.apparent_temperature),
      weatherCode: current.weather_code,
    },
    daily: parseDaily(data),
  };

  setCache('forecast', {
    key: cacheKey,
    ts: Date.now(),
    data: forecast,
  });

  return forecast;
}

const WEATHER_LABELS = {
  0: '晴',
  1: '少云',
  2: '多云',
  3: '阴',
  45: '雾',
  48: '雾凇',
  51: '小毛毛雨',
  53: '毛毛雨',
  55: '强毛毛雨',
  61: '小雨',
  63: '雨',
  65: '大雨',
  71: '小雪',
  73: '雪',
  75: '大雪',
  80: '阵雨',
  81: '阵雨',
  82: '强阵雨',
  95: '雷暴',
};

function describeWeather(code) {
  if (code === null || code === undefined) return '未知';
  return WEATHER_LABELS[code] || '未知';
}

module.exports = {
  getForecast,
  describeWeather,
};
