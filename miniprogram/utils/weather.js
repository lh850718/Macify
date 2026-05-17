const { getCache, setCache } = require('./storage.js');

const GEOCODE_URL = 'https://geocoding-api.open-meteo.com/v1/search';
const FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';
const FORECAST_TTL_MS = 30 * 60 * 1000;
const KNOWN_CITY_GEOS = Object.freeze({
  beijing: {
    lat: 39.9075,
    lng: 116.39723,
    name: '北京',
    country: 'CN',
  },
  '北京': {
    lat: 39.9075,
    lng: 116.39723,
    name: '北京',
    country: 'CN',
  },
  peking: {
    lat: 39.9075,
    lng: 116.39723,
    name: '北京',
    country: 'CN',
  },
  shanghai: {
    lat: 31.22222,
    lng: 121.45806,
    name: '上海',
    country: 'CN',
  },
  '上海': {
    lat: 31.22222,
    lng: 121.45806,
    name: '上海',
    country: 'CN',
  },
});

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
          if (typeof response.data === 'string') {
            try {
              resolve(JSON.parse(response.data));
              return;
            } catch (error) {
              reject(error);
              return;
            }
          }
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
  if (KNOWN_CITY_GEOS[key]) return KNOWN_CITY_GEOS[key];

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
    precipitationSum: roundOrNull(arrayItem(daily.precipitation_sum, index)),
    windSpeed: roundOrNull(arrayItem(daily.wind_speed_10m_max, index)),
    uvIndex: roundOrNull(arrayItem(daily.uv_index_max, index)),
    sunrise: arrayItem(daily.sunrise, index),
    sunset: arrayItem(daily.sunset, index),
  }));
}

async function fetchForecast(geo, tempUnit) {
  const query = buildQuery({
    latitude: geo.lat,
    longitude: geo.lng,
    current: 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
    daily: [
      'weather_code',
      'temperature_2m_max',
      'temperature_2m_min',
      'precipitation_probability_max',
      'precipitation_sum',
      'wind_speed_10m_max',
      'uv_index_max',
      'sunrise',
      'sunset',
    ].join(','),
    forecast_days: 7,
    temperature_unit: tempUnit === 'fahrenheit' ? 'fahrenheit' : 'celsius',
    wind_speed_unit: 'kmh',
    precipitation_unit: 'mm',
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

  try {
    const geo = await geocodeCity(city);
    const data = await fetchForecast(geo, tempUnit);
    const current = data.current || {};
    const forecast = {
      location: geo.name,
      unit: tempUnit === 'fahrenheit' ? 'F' : 'C',
      current: {
        temperature: roundOrNull(current.temperature_2m),
        feelsLike: roundOrNull(current.apparent_temperature),
        humidity: roundOrNull(current.relative_humidity_2m),
        weatherCode: current.weather_code,
        windSpeed: roundOrNull(current.wind_speed_10m),
      },
      daily: parseDaily(data),
    };

    setCache('forecast', {
      key: cacheKey,
      ts: Date.now(),
      data: forecast,
    });

    return forecast;
  } catch (error) {
    if (cached && cached.data) return cached.data;
    throw error;
  }
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
