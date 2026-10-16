#include "../../src/entity/BNEEntityTracker.h"
#include "../../src/data_source/BNEDataSource.h"
#include "../../src/projection/BNEProjection.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    BNEObservation reset = {0};
    reset.type = BNE_EVENT_SESSION_RESET;
    snprintf(reset.session_id, sizeof(reset.session_id), "fixture-session");
    assert(bne_tracker_apply(&tracker, &reset) == BNE_APPLY_ACCEPTED);

    BNEObservation observation = {0};
    observation.type = BNE_EVENT_SPAWN;
    observation.source = BNE_SOURCE_TEST_FIXTURE;
    snprintf(observation.session_id, sizeof(observation.session_id), "fixture-session");
    snprintf(observation.entity_type_id, sizeof(observation.entity_type_id), "minecraft:cow");
    observation.runtime_id = 22;
    observation.sequence = 1;
    observation.observed_at_ms = 100;
    observation.has_position = true;
    observation.position[0] = 0;
    observation.position[1] = 0;
    observation.position[2] = 0;
    assert(bne_tracker_apply(&tracker, &observation) == BNE_APPLY_ACCEPTED);

    BNESnapshot snapshot;
    assert(bne_tracker_snapshot(&tracker, 110, 1000, &snapshot));
    assert(snapshot.count == 1);
    const double identity[16] = {
        1, 0, 0, 0, 0, 1, 0, 0,
        0, 0, 1, 0, 0, 0, 0, 1
    };
    const double bounds[3] = {1, 1, 1};
    BNEProjectedRect rectangle;
    assert(bne_project_aabb(identity, snapshot.entities[0].position, bounds,
                            -1, 1, 0, 0, 1000, 500, &rectangle));
    assert(rectangle.width > 0 && rectangle.height > 0);

    BNEObservation incomplete = observation;
    incomplete.runtime_id = 23;
    incomplete.entity_type_id[0] = '\0';
    incomplete.sequence = 1;
    assert(bne_tracker_apply(&tracker, &incomplete) == BNE_APPLY_REJECTED);
    incomplete.type = BNE_EVENT_SPAWN;
    snprintf(incomplete.entity_type_id, sizeof(incomplete.entity_type_id), "minecraft:zombie");
    incomplete.has_position = false;
    assert(bne_tracker_apply(&tracker, &incomplete) == BNE_APPLY_ACCEPTED);
    assert(bne_tracker_snapshot(&tracker, 110, 1000, &snapshot));
    assert(snapshot.count == 1);
    puts("fixture pipeline passed; no live source or camera was exercised");
    return 0;
}