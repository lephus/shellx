import 'package:shellx_ai/remote.dart';
import 'package:test/test.dart';

/// V2-2b B1: what a window's hub does beyond V2-2a, in its listing (`f`).
void main() {
  test('the features go as a sorted f, and come back', () {
    const listing = AiListing(
      features: {AiFeature.revert, AiFeature.config, AiFeature.acpHead},
    );
    final json = listing.toJson();
    expect(json['f'], ['acp_head', 'config', 'revert']);
    expect(AiListing.fromJson(json, available: true).features, {
      'acp_head',
      'config',
      'revert',
    });
  });

  test('without features the body is a V2-2a body: no f; an older hub\'s '
      'listing has none', () {
    expect(const AiListing().toJson().containsKey('f'), isFalse);
    expect(
      AiListing.fromJson(const AiListing().toJson(), available: true).features,
      isEmpty,
    );
  });

  test('anything in f that is no string is skipped; an f that is no list is '
      'none', () {
    expect(
      AiListing.fromJson({
        'f': ['config', 7, null, 'item'],
      }, available: true).features,
      {'config', 'item'},
    );
    expect(
      AiListing.fromJson({'f': 'config'}, available: true).features,
      isEmpty,
    );
  });

  test('the words of V2-2b (spec B1)', () {
    expect(
      {
        AiFeature.config,
        AiFeature.blob,
        AiFeature.files,
        AiFeature.changes,
        AiFeature.revert,
        AiFeature.item,
        AiFeature.history,
        AiFeature.folder,
        AiFeature.pushAnswer,
        AiFeature.acpHead,
      },
      {
        'config',
        'blob',
        'files',
        'changes',
        'revert',
        'item',
        'history',
        'folder',
        'push_answer',
        'acp_head',
      },
    );
  });
}
