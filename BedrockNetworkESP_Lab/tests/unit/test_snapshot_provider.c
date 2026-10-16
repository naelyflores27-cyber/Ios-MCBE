#include "../../src/entity/BNEEntitySnapshotProvider.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    assert(bne_entity_snapshot_provider_reset_session("provider-session-a"));
    BNEObservation observation = {0};
    observation.type = BNE_EVENT_SPAWN;
    observation.source = BNE_SOURCE_TEST_FIXTURE;
    snprintf(observation.session_id, sizeof(observation.session_id),
             "provider-session-a");
    snprintf(observation.entity_type_id, sizeof(observation.entity_type_id),
             "minecraft:cow");
    observation.runtime_id = 5;
    observation.sequence = 1;
    observation.observed_at_ms = 100;
    observation.has_position = true;
    observation.position[0] = 3;
    observation.position[1] = 64;
    observation.position[2] = -2;
    assert(bne_entity_snapshot_provider_apply(&observation) == BNE_APPLY_ACCEPTED);

    BNESnapshot snapshot;
    assert(bne_entity_snapshot_provider_copy(110, 1000, &snapshot));
    assert(snapshot.count == 1);
    assert(snapshot.entities[0].runtime_id == 5);

    assert(bne_entity_snapshot_provider_reset_session("provider-session-b"));
    assert(bne_entity_snapshot_provider_copy(120, 1000, &snapshot));
    assert(snapshot.count == 0);

    char invalid_session[BNE_SESSION_ID_CAPACITY];
    memset(invalid_session, 'x', sizeof(invalid_session));
    assert(!bne_entity_snapshot_provider_reset_session(invalid_session));
    puts("snapshot provider tests passed");
    return 0;
}