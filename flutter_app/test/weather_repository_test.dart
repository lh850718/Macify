import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/weather/weather_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads Open-Meteo forecast and maps weather labels', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeWeatherApiClient();
    final repository = OpenMeteoWeatherRepository(client: client);

    final forecast = await repository.getForecast(
      city: '北京',
      temperatureUnit: 'celsius',
    );

    expect(forecast.location, '北京');
    expect(forecast.unit, 'C');
    expect(forecast.current.temperature, 22);
    expect(forecast.current.feelsLike, 21);
    expect(describeWeather(forecast.current.weatherCode), '晴');
    expect(forecast.daily, hasLength(2));
    expect(forecast.daily.first.max, 25);
  });

  test('returns cached forecast when refresh fails', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _FakeWeatherApiClient();
    final repository = OpenMeteoWeatherRepository(
      client: client,
      cacheTtl: Duration.zero,
    );

    await repository.getForecast(city: '北京', temperatureUnit: 'celsius');
    client.failForecast = true;

    final cached = await repository.getForecast(
      city: '北京',
      temperatureUnit: 'celsius',
    );

    expect(cached.current.temperature, 22);
  });
}

class _FakeWeatherApiClient implements WeatherApiClient {
  var failForecast = false;

  @override
  Future<Map<String, dynamic>> getJson(Uri uri) async {
    if (uri.host == 'api.open-meteo.com') {
      if (failForecast) throw const WeatherException('offline');
      return {
        'current': {
          'temperature_2m': 21.7,
          'apparent_temperature': 20.8,
          'relative_humidity_2m': 53,
          'weather_code': 0,
          'wind_speed_10m': 11.2,
        },
        'daily': {
          'time': ['2026-05-31', '2026-06-01'],
          'weather_code': [0, 61],
          'temperature_2m_max': [25.2, 23.4],
          'temperature_2m_min': [15.1, 14.8],
          'precipitation_probability_max': [0, 48],
          'precipitation_sum': [0, 3.2],
          'wind_speed_10m_max': [18.1, 20.4],
          'uv_index_max': [7.4, 5.2],
          'sunrise': ['2026-05-31T04:49', '2026-06-01T04:48'],
          'sunset': ['2026-05-31T19:34', '2026-06-01T19:35'],
        },
      };
    }
    throw WeatherException('Unexpected URI $uri');
  }
}
