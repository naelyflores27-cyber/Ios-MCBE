#include "../../src/entity/BNEEntityTracker.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static BNEObservation event(BNEEventType type, uint64_t id, uint64_t sequence,
                            uint64_t time_ms) {
    BNEObservation value = {0};
    value.type = type;
    value.source = BNE_SOURCE_TEST_FIXTURE;
    snprintf(value.session_id, sizeof(value.session_id), "session-a");
    value.runtime_id = id;
    value.observed_at_ms = time_ms;
    value.sequence = sequence;
    return value;
}

static void reset(BNEEntityTracker *tracker, const char *session_id) {
    BNEObservation value = event(BNE_EVENT_SESSION_RESET, 0, 0, 1);
    snprintf(value.session_id, sizeof(value.session_id), "%s", session_id);
    assert(bne_tracker_apply(tracker, &value) == BNE_APPLY_ACCEPTED);
}

static BNEObservation spawn(uint64_t id, uint64_t sequence, uint64_t time_ms,
                            const char *type, double x) {
    BNEObservation value = event(BNE_EVENT_SPAWN, id, sequence, time_ms);
    snprintf(value.entity_type_id, sizeof(value.entity_type_id), "%s", type);
    value.has_position = true;
    value.position[0] = x;
    value.position[1] = 64;
    value.position[2] = -12;
    return value;
}

static void test_entities_updates_and_snapshot_copy(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    reset(&tracker, "session-a");
    BNEObservation cow_one = spawn(100, 1, 100, "minecraft:cow", 1);
    BNEObservation cow_two = spawn(101, 1, 100, "minecraft:cow", 2);
    assert(bne_tracker_apply(&tracker, &cow_one) == BNE_APPLY_ACCEPTED);
    assert(bne_tracker_apply(&tracker, &cow_two) == BNE_APPLY_ACCEPTED);

    BNEObservation update = event(BNE_EVENT_UPDATE, 100, 2, 200);
    update.has_position = true;
    update.position[0] = 9;
    update.position[1] = 65;
    update.position[2] = -12;
    update.has_rotation = true;
    update.rotation[1] = 90;
    assert(bne_tracker_apply(&tracker, &update) == BNE_APPLY_ACCEPTED);

    BNESnapshot snapshot;
    assert(bne_tracker_snapshot(&tracker, 220, 1000, &snapshot));
    assert(snapshot.count == 2);
    assert(snapshot.diagnostics.valid_position_count == 2);
    assert(snapshot.entities[0].position[0] == 9);
    assert(snapshot.entities[0].has_rotation);
    snapshot.entities[0].position[0] = -500;
    assert(tracker.entities[0].position[0] == 9);
}

static void test_incomplete_invalid_duplicate_out_of_order_and_remove(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    reset(&tracker, "session-a");

    BNEObservation incomplete = event(BNE_EVENT_SPAWN, 42, 1, 100);
    snprintf(incomplete.entity_type_id, sizeof(incomplete.entity_type_id), "minecraft:zombie");
    assert(bne_tracker_apply(&tracker, &incomplete) == BNE_APPLY_ACCEPTED);
    BNESnapshot snapshot;
    assert(bne_tracker_snapshot(&tracker, 110, 1000, &snapshot));
    assert(snapshot.count == 0);
    assert(snapshot.diagnostics.incomplete_count == 1);

    BNEObservation invalid = event(BNE_EVENT_UPDATE, 42, 2, 200);
    invalid.has_position = true;
    invalid.position[0] = NAN;
    assert(bne_tracker_apply(&tracker, &invalid) == BNE_APPLY_REJECTED);

    BNEObservation update = event(BNE_EVENT_UPDATE, 42, 2, 200);
    update.has_position = true;
    update.position[0] = 4;
    update.position[1] = 65;
    update.position[2] = 8;
    assert(bne_tracker_apply(&tracker, &update) == BNE_APPLY_ACCEPTED);
    assert(bne_tracker_apply(&tracker, &update) == BNE_APPLY_IGNORED);

    BNEObservation old = update;
    old.sequence = 1;
    old.observed_at_ms = 150;
    old.position[0] = 99;
    assert(bne_tracker_apply(&tracker, &old) == BNE_APPLY_IGNORED);

    assert(bne_tracker_snapshot(&tracker, 220, 1000, &snapshot));
    assert(snapshot.count == 1);
    assert(snapshot.entities[0].position[0] == 4);

    BNEObservation remove = event(BNE_EVENT_REMOVE, 42, 3, 300);
    assert(bne_tracker_apply(&tracker, &remove) == BNE_APPLY_ACCEPTED);
    assert(bne_tracker_snapshot(&tracker, 320, 1000, &snapshot));
    assert(snapshot.count == 0);
    assert(snapshot.diagnostics.removal_count == 1);
}

static void test_stale_reset_reuse_and_session_isolation(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    reset(&tracker, "session-a");
    BNEObservation first = spawn(7, 1, 100, "minecraft:skeleton", 3);
    assert(bne_tracker_apply(&tracker, &first) == BNE_APPLY_ACCEPTED);

    BNESnapshot snapshot;
    assert(bne_tracker_snapshot(&tracker, 500, 100, &snapshot));
    assert(snapshot.count == 0);
    assert(snapshot.diagnostics.stale_count == 1);

    reset(&tracker, "session-b");
    assert(tracker.count == 0);
    assert(tracker.session_generation == 2);
    assert(bne_tracker_apply(&tracker, &first) == BNE_APPLY_REJECTED);

    BNEObservation reused = spawn(7, 1, 600, "minecraft:cow", 11);
    snprintf(reused.session_id, sizeof(reused.session_id), "session-b");
    assert(bne_tracker_apply(&tracker, &reused) == BNE_APPLY_ACCEPTED);
    assert(bne_tracker_snapshot(&tracker, 610, 1000, &snapshot));
    assert(snapshot.count == 1);
    assert(strcmp(snapshot.entities[0].entity_type_id, "minecraft:cow") == 0);
    assert(snapshot.entities[0].session_generation == 2);
}

static void test_metadata_event_does_not_refresh_old_position(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    reset(&tracker, "session-a");
    BNEObservation first = spawn(9, 1, 100, "minecraft:cow", 3);
    assert(bne_tracker_apply(&tracker, &first) == BNE_APPLY_ACCEPTED);

    BNEObservation metadata = event(BNE_EVENT_UPDATE, 9, 2, 300);
    assert(bne_tracker_apply(&tracker, &metadata) == BNE_APPLY_ACCEPTED);
    BNESnapshot snapshot;
    assert(bne_tracker_snapshot(&tracker, 350, 100, &snapshot));
    assert(snapshot.count == 0);
    assert(snapshot.diagnostics.stale_count == 1);
    assert(tracker.entities[0].position_source == BNE_SOURCE_TEST_FIXTURE);
    assert(tracker.entities[0].position_observed_at_ms == 100);
    assert(bne_tracker_snapshot(&tracker, 350, 50, &snapshot));
    assert(snapshot.count == 0);
    assert(snapshot.diagnostics.stale_count == 1);
}

static void test_unterminated_type_identifier_is_rejected(void) {
    BNEEntityTracker tracker;
    bne_tracker_init(&tracker);
    reset(&tracker, "session-a");
    BNEObservation malformed = event(BNE_EVENT_SPAWN, 12, 1, 100);
    memset(malformed.entity_type_id, 'x', sizeof(malformed.entity_type_id));
    assert(bne_tracker_apply(&tracker, &malformed) == BNE_APPLY_REJECTED);
    assert(tracker.count == 0);
}

int main(void) {
    test_entities_updates_and_snapshot_copy();
    test_incomplete_invalid_duplicate_out_of_order_and_remove();
    test_stale_reset_reuse_and_session_isolation();
    test_metadata_event_does_not_refresh_old_position();
    test_unterminated_type_identifier_is_rejected();
    puts("entity tracker tests passed");
    return 0;
}