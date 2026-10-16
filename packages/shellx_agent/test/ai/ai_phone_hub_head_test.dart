import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// V2-2b B1, B22: the window's listing names `acp_head` — its headers carry
/// the agent's session id — and a phone that attaches gets it.
void main() {
  test('the listing offers acp_head; the header carries acp', () {
    final rig = HubRig();
    rig.source.add(-1).setSession('sess-1');
    rig.hub.handle(_phone, const AiList());
    final listing = AiListing.fromJson(
      decodeBody(rig.last<AiListResult>(_phone).body)!,
      available: true,
    );
    expect(listing.features, contains(AiFeature.acpHead));
    rig.hub.handle(_phone, const AiAttach(sid: 'ep.-1'));
    expect(rig.mirror(_phone, 'ep.-1').head!.acp, 'sess-1');
  });
}
