import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class WeatherForecastRepository {
  Future<WeatherForecast> getForecast({
    required String city,
    required String temperatureUnit,
  });
}

abstract interface class WeatherApiClient {
  Future<Map<String, dynamic>> getJson(Uri uri);
}

class HttpWeatherApiClient implements WeatherApiClient {
  HttpWeatherApiClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<Map<String, dynamic>> getJson(Uri uri) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WeatherException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const WeatherException('Unexpected weather response');
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }
}

class OpenMeteoWeatherRepository implements WeatherForecastRepository {
  OpenMeteoWeatherRepository({
    WeatherApiClient? client,
    this.cacheTtl = const Duration(minutes: 30),
  }) : _client = client ?? HttpWeatherApiClient();

  static const _geocodeHost = 'geocoding-api.open-meteo.com';
  static const _forecastHost = 'api.open-meteo.com';
  static const _geocodeCacheKey = 'weather-geocode-cache-v1';
  static const _forecastCacheKey = 'weather-forecast-cache-v1';

  final WeatherApiClient _client;
  final Duration cacheTtl;

  @override
  Future<WeatherForecast> getForecast({
    required String city,
    required String temperatureUnit,
  }) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) {
      throw const WeatherException('City is empty');
    }
    final unit = temperatureUnit == 'fahrenheit' ? 'fahrenheit' : 'celsius';
    final cacheKey = '${normalizedCity.toLowerCase()}|$unit';
    final prefs = await SharedPreferences.getInstance();
    final cached = _readForecastCache(prefs);

    if (cached != null &&
        cached.key == cacheKey &&
        DateTime.now().millisecondsSinceEpoch - cached.timestampMs <
            cacheTtl.inMilliseconds) {
      return cached.forecast;
    }

    try {
      final geo = await _geocodeCity(normalizedCity, prefs);
      final forecast = _parseForecast(
        await _client.getJson(_forecastUri(geo, unit)),
        geo,
        unit,
      );
      await prefs.setString(
        _forecastCacheKey,
        jsonEncode(
          _ForecastCacheEntry(
            key: cacheKey,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            forecast: forecast,
          ).toJson(),
        ),
      );
      return forecast;
    } catch (_) {
      if (cached != null && cached.key == cacheKey) return cached.forecast;
      rethrow;
    }
  }

  void close({bool force = false}) {
    final client = _client;
    if (client is HttpWeatherApiClient) client.close(force: force);
  }

  Future<_GeoLocation> _geocodeCity(
    String city,
    SharedPreferences prefs,
  ) async {
    final key = city.trim().toLowerCase();
    final known = _knownCityGeos[key];
    if (known != null) return known;

    final cached = _readGeocodeCache(prefs);
    final cachedGeo = cached[key];
    if (cachedGeo != null) return cachedGeo;

    final data = await _client.getJson(
      Uri.https(_geocodeHost, '/v1/search', {
        'name': city,
        'count': '1',
        'language': 'zh',
        'format': 'json',
      }),
    );
    final results = data['results'];
    final result = results is List && results.isNotEmpty ? results.first : null;
    if (result is! Map) {
      throw WeatherException('No geocode result for $city');
    }
    final latitude = _doubleValue(result['latitude']);
    final longitude = _doubleValue(result['longitude']);
    if (latitude == null || longitude == null) {
      throw WeatherException('Invalid geocode result for $city');
    }

    final geo = _GeoLocation(
      lat: latitude,
      lng: longitude,
      name: (result['name'] as String?)?.trim().isNotEmpty == true
          ? (result['name'] as String).trim()
          : city,
      country: (result['country_code'] as String?) ?? '',
    );
    cached[key] = geo;
    await prefs.setString(
      _geocodeCacheKey,
      jsonEncode({
        for (final entry in cached.entries) entry.key: entry.value.toJson(),
      }),
    );
    return geo;
  }

  Uri _forecastUri(_GeoLocation geo, String unit) {
    return Uri.https(_forecastHost, '/v1/forecast', {
      'latitude': geo.lat.toString(),
      'longitude': geo.lng.toString(),
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
      'daily': [
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
      'forecast_days': '7',
      'temperature_unit': unit,
      'wind_speed_unit': 'kmh',
      'precipitation_unit': 'mm',
      'timezone': 'auto',
    });
  }

  WeatherForecast _parseForecast(
    Map<String, dynamic> data,
    _GeoLocation geo,
    String unit,
  ) {
    final current = data['current'];
    if (current is! Map) {
      throw const WeatherException('Missing current weather');
    }
    return WeatherForecast(
      location: geo.name,
      unit: unit == 'fahrenheit' ? 'F' : 'C',
      current: WeatherCurrent(
        temperature: _roundOrNull(current['temperature_2m']),
        feelsLike: _roundOrNull(current['apparent_temperature']),
        humidity: _roundOrNull(current['relative_humidity_2m']),
        weatherCode: _intValue(current['weather_code']),
        windSpeed: _roundOrNull(current['wind_speed_10m']),
      ),
      daily: _parseDaily(data['daily']),
    );
  }

  List<WeatherDaily> _parseDaily(Object? raw) {
    if (raw is! Map) return const [];
    final times = raw['time'];
    if (times is! List) return const [];
    return [
      for (var index = 0; index < times.length; index += 1)
        WeatherDaily(
          date: '${times[index]}',
          weatherCode: _intValue(_arrayItem(raw['weather_code'], index)),
          max: _roundOrNull(_arrayItem(raw['temperature_2m_max'], index)),
          min: _roundOrNull(_arrayItem(raw['temperature_2m_min'], index)),
          precipitation: _roundOrNull(
            _arrayItem(raw['precipitation_probability_max'], index),
          ),
          precipitationSum: _roundOrNull(
            _arrayItem(raw['precipitation_sum'], index),
          ),
          windSpeed: _roundOrNull(_arrayItem(raw['wind_speed_10m_max'], index)),
          uvIndex: _roundOrNull(_arrayItem(raw['uv_index_max'], index)),
          sunrise: _stringValue(_arrayItem(raw['sunrise'], index)),
          sunset: _stringValue(_arrayItem(raw['sunset'], index)),
        ),
    ];
  }

  Map<String, _GeoLocation> _readGeocodeCache(SharedPreferences prefs) {
    final raw = prefs.getString(_geocodeCacheKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: _GeoLocation.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  _ForecastCacheEntry? _readForecastCache(SharedPreferences prefs) {
    final raw = prefs.getString(_forecastCacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _ForecastCacheEntry.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

class WeatherForecast {
  const WeatherForecast({
    required this.location,
    required this.unit,
    required this.current,
    required this.daily,
  });

  final String location;
  final String unit;
  final WeatherCurrent current;
  final List<WeatherDaily> daily;

  Map<String, dynamic> toJson() => {
    'location': location,
    'unit': unit,
    'current': current.toJson(),
    'daily': daily.map((day) => day.toJson()).toList(growable: false),
  };

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    final daily = json['daily'];
    return WeatherForecast(
      location: (json['location'] as String?) ?? '',
      unit: (json['unit'] as String?) ?? 'C',
      current: WeatherCurrent.fromJson(
        Map<String, dynamic>.from((json['current'] as Map?) ?? const {}),
      ),
      daily: daily is List
          ? daily
                .whereType<Map>()
                .map(
                  (item) =>
                      WeatherDaily.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class WeatherCurrent {
  const WeatherCurrent({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.weatherCode,
    required this.windSpeed,
  });

  final int? temperature;
  final int? feelsLike;
  final int? humidity;
  final int? weatherCode;
  final int? windSpeed;

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'feelsLike': feelsLike,
    'humidity': humidity,
    'weatherCode': weatherCode,
    'windSpeed': windSpeed,
  };

  factory WeatherCurrent.fromJson(Map<String, dynamic> json) => WeatherCurrent(
    temperature: _intValue(json['temperature']),
    feelsLike: _intValue(json['feelsLike']),
    humidity: _intValue(json['humidity']),
    weatherCode: _intValue(json['weatherCode']),
    windSpeed: _intValue(json['windSpeed']),
  );
}

class WeatherDaily {
  const WeatherDaily({
    required this.date,
    required this.weatherCode,
    required this.max,
    required this.min,
    required this.precipitation,
    required this.precipitationSum,
    required this.windSpeed,
    required this.uvIndex,
    required this.sunrise,
    required this.sunset,
  });

  final String date;
  final int? weatherCode;
  final int? max;
  final int? min;
  final int? precipitation;
  final int? precipitationSum;
  final int? windSpeed;
  final int? uvIndex;
  final String? sunrise;
  final String? sunset;

  Map<String, dynamic> toJson() => {
    'date': date,
    'weatherCode': weatherCode,
    'max': max,
    'min': min,
    'precipitation': precipitation,
    'precipitationSum': precipitationSum,
    'windSpeed': windSpeed,
    'uvIndex': uvIndex,
    'sunrise': sunrise,
    'sunset': sunset,
  };

  factory WeatherDaily.fromJson(Map<String, dynamic> json) => WeatherDaily(
    date: (json['date'] as String?) ?? '',
    weatherCode: _intValue(json['weatherCode']),
    max: _intValue(json['max']),
    min: _intValue(json['min']),
    precipitation: _intValue(json['precipitation']),
    precipitationSum: _intValue(json['precipitationSum']),
    windSpeed: _intValue(json['windSpeed']),
    uvIndex: _intValue(json['uvIndex']),
    sunrise: _stringValue(json['sunrise']),
    sunset: _stringValue(json['sunset']),
  );
}

class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;

  @override
  String toString() => 'WeatherException: $message';
}

String describeWeather(int? code) {
  if (code == null) return '未知';
  return _weatherLabels[code] ?? '未知';
}

class _GeoLocation {
  const _GeoLocation({
    required this.lat,
    required this.lng,
    required this.name,
    required this.country,
  });

  final double lat;
  final double lng;
  final String name;
  final String country;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'name': name,
    'country': country,
  };

  factory _GeoLocation.fromJson(Map<String, dynamic> json) => _GeoLocation(
    lat: _doubleValue(json['lat']) ?? 0,
    lng: _doubleValue(json['lng']) ?? 0,
    name: (json['name'] as String?) ?? '',
    country: (json['country'] as String?) ?? '',
  );
}

class _ForecastCacheEntry {
  const _ForecastCacheEntry({
    required this.key,
    required this.timestampMs,
    required this.forecast,
  });

  final String key;
  final int timestampMs;
  final WeatherForecast forecast;

  Map<String, dynamic> toJson() => {
    'key': key,
    'timestampMs': timestampMs,
    'forecast': forecast.toJson(),
  };

  factory _ForecastCacheEntry.fromJson(Map<String, dynamic> json) =>
      _ForecastCacheEntry(
        key: (json['key'] as String?) ?? '',
        timestampMs: _intValue(json['timestampMs']) ?? 0,
        forecast: WeatherForecast.fromJson(
          Map<String, dynamic>.from((json['forecast'] as Map?) ?? const {}),
        ),
      );
}

const _knownCityGeos = {
  'beijing': _GeoLocation(
    lat: 39.9075,
    lng: 116.39723,
    name: '北京',
    country: 'CN',
  ),
  '北京': _GeoLocation(lat: 39.9075, lng: 116.39723, name: '北京', country: 'CN'),
  'peking': _GeoLocation(
    lat: 39.9075,
    lng: 116.39723,
    name: '北京',
    country: 'CN',
  ),
  'shanghai': _GeoLocation(
    lat: 31.22222,
    lng: 121.45806,
    name: '上海',
    country: 'CN',
  ),
  '上海': _GeoLocation(lat: 31.22222, lng: 121.45806, name: '上海', country: 'CN'),
};

const _weatherLabels = {
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

Object? _arrayItem(Object? raw, int index) {
  if (raw is! List || index < 0 || index >= raw.length) return null;
  return raw[index];
}

int? _roundOrNull(Object? value) {
  final number = _doubleValue(value);
  return number?.round();
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String? _stringValue(Object? value) => value == null ? null : '$value';
