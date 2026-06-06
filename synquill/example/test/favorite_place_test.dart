import 'package:flutter_test/flutter_test.dart';
import 'package:synquill_example/models/index.dart';

void main() {
  test('FavoritePlace serializes internal id as placeId', () {
    final place = FavoritePlace(
      id: 'place-1',
      title: 'Trailhead',
      address: 'North Ridge',
    );

    final json = place.toJson();

    expect(json['placeId'], 'place-1');
    expect(json.containsKey('id'), isFalse);
    expect(FavoritePlace.fromJson(json).id, 'place-1');
  });
}
