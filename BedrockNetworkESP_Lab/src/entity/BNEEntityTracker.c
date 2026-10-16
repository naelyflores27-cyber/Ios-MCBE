#include "BNEEntityTracker.h"

#include <math.h>
#include <string.h>

static bool bne_text_is_valid(const char *text, size_t capacity) {
    return text && text[0] != '\0' && memchr(text, '\0', capacity) != NULL;
}

static bool bne_vector_is_finite(const double vector[3]) {
    return isfinite(vector[0]) && isfinite(vector[1]) && isfinite(vector[2]);
}

static bool bne_position_is_valid(const double position[3]) {
    return bne_vector_is_finite(position);
}

static size_t bne_find_entity(const BNEEntityTracker *tracker, uint64_t runtime_id) {
    for (size_t index = 0; index < tracker->count; index++) {
        if (tracker->entities[index].runtime_id == runtime_id) return index;
    }
    return tracker->count;
}

void bne_tracker_init(BNEEntityTracker *tracker) {
    if (tracker) memset(tracker, 0, sizeof(*tracker));
}

BNEApplyResult bne_tracker_apply(BNEEntityTracker *tracker,
                                 const BNEObservation *observation) {
    if (!tracker || !observation) return BNE_APPLY_REJECTED;
    tracker->diagnostics.event_count++;

    if (observation->type == BNE_EVENT_SESSION_RESET) {
        if (!bne_text_is_valid(observation->session_id, sizeof(observation->session_id))) {
            tracker->diagnostics.rejected_count++;
            return BNE_APPLY_REJECTED;
        }
        if (strcmp(tracker->session_id, observation->session_id) == 0) {
            return BNE_APPLY_IGNORED;
        }
        memset(tracker->entities, 0, sizeof(tracker->entities));
        tracker->count = 0;
        memcpy(tracker->session_id, observation->session_id, sizeof(tracker->session_id));
        tracker->session_generation++;
        return BNE_APPLY_ACCEPTED;
    }

    if (!bne_text_is_valid(observation->session_id, sizeof(observation->session_id)) ||
        strcmp(tracker->session_id, observation->session_id) != 0 ||
        observation->sequence == 0 || observation->observed_at_ms == 0 ||
        observation->source < BNE_SOURCE_TEST_FIXTURE ||
            observation->source > BNE_SOURCE_SERVER_GROUND_TRUTH ||
            (observation->entity_type_id[0] != '\0' &&
             !bne_text_is_valid(observation->entity_type_id,
                                sizeof(observation->entity_type_id)))) {
        tracker->diagnostics.rejected_count++;
        return BNE_APPLY_REJECTED;
    }

    size_t index = bne_find_entity(tracker, observation->runtime_id);
    if (observation->type == BNE_EVENT_REMOVE) {
        if (index == tracker->count) return BNE_APPLY_IGNORED;
        BNEEntitySnapshot *entity = &tracker->entities[index];
        if (observation->observed_at_ms < entity->last_observed_at_ms ||
            observation->sequence <= entity->last_sequence) {
            return BNE_APPLY_IGNORED;
        }
        tracker->entities[index] = tracker->entities[tracker->count - 1];
        memset(&tracker->entities[tracker->count - 1], 0, sizeof(tracker->entities[0]));
        tracker->count--;
        tracker->diagnostics.removal_count++;
        return BNE_APPLY_ACCEPTED;
    }

    if (observation->type != BNE_EVENT_SPAWN && observation->type != BNE_EVENT_UPDATE) {
        tracker->diagnostics.rejected_count++;
        return BNE_APPLY_REJECTED;
    }
    if (observation->type == BNE_EVENT_SPAWN &&
        !bne_text_is_valid(observation->entity_type_id, sizeof(observation->entity_type_id))) {
        tracker->diagnostics.rejected_count++;
        return BNE_APPLY_REJECTED;
    }
    if (observation->has_position && !bne_position_is_valid(observation->position)) {
        tracker->diagnostics.rejected_count++;
        return BNE_APPLY_REJECTED;
    }
    if (observation->has_rotation && !bne_vector_is_finite(observation->rotation)) {
        tracker->diagnostics.rejected_count++;
        return BNE_APPLY_REJECTED;
    }

    if (index != tracker->count) {
        BNEEntitySnapshot *entity = &tracker->entities[index];
        if (observation->observed_at_ms < entity->last_observed_at_ms ||
            observation->sequence <= entity->last_sequence) {
            return BNE_APPLY_IGNORED;
        }
        if (observation->entity_type_id[0] != '\0' &&
            strcmp(entity->entity_type_id, observation->entity_type_id) != 0) {
            tracker->diagnostics.rejected_count++;
            return BNE_APPLY_REJECTED;
        }
    } else {
        if (observation->type != BNE_EVENT_SPAWN || tracker->count == BNE_MAX_ENTITIES) {
            tracker->diagnostics.rejected_count++;
            return BNE_APPLY_REJECTED;
        }
        index = tracker->count++;
        memset(&tracker->entities[index], 0, sizeof(tracker->entities[index]));
        tracker->entities[index].runtime_id = observation->runtime_id;
        memcpy(tracker->entities[index].entity_type_id, observation->entity_type_id,
               sizeof(tracker->entities[index].entity_type_id));
    }

    BNEEntitySnapshot *entity = &tracker->entities[index];
    if (observation->has_position) {
        memcpy(entity->position, observation->position, sizeof(entity->position));
        entity->has_position = true;
        entity->position_source = observation->source;
        entity->position_observed_at_ms = observation->observed_at_ms;
    }
    if (observation->has_rotation) {
        memcpy(entity->rotation, observation->rotation, sizeof(entity->rotation));
        entity->has_rotation = true;
        entity->rotation_source = observation->source;
    }
    entity->last_observed_at_ms = observation->observed_at_ms;
    entity->last_sequence = observation->sequence;
    entity->session_generation = tracker->session_generation;
    entity->source = observation->source;
    tracker->diagnostics.update_count++;
    return BNE_APPLY_ACCEPTED;
}

bool bne_tracker_snapshot(const BNEEntityTracker *tracker,
                          uint64_t now_ms,
                          uint64_t max_age_ms,
                          BNESnapshot *snapshot) {
    if (!tracker || !snapshot || now_ms == 0 || max_age_ms == 0) return false;
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->session_generation = tracker->session_generation;
    snapshot->published_at_ms = now_ms;
    snapshot->diagnostics = tracker->diagnostics;
    snapshot->diagnostics.tracked_count = tracker->count;

    for (size_t index = 0; index < tracker->count; index++) {
        const BNEEntitySnapshot *entity = &tracker->entities[index];
        if (!entity->has_position || entity->position_observed_at_ms == 0) {
            snapshot->diagnostics.incomplete_count++;
            continue;
        }
        if (entity->position_observed_at_ms > now_ms) {
            snapshot->diagnostics.stale_count++;
            continue;
        }
        uint64_t age = now_ms >= entity->position_observed_at_ms
            ? now_ms - entity->position_observed_at_ms : 0;
        if (age > max_age_ms) {
            snapshot->diagnostics.stale_count++;
            continue;
        }
        if (entity->session_generation != tracker->session_generation ||
            entity->entity_type_id[0] == '\0' ||
            !bne_position_is_valid(entity->position)) continue;
        snapshot->entities[snapshot->count++] = *entity;
        snapshot->diagnostics.valid_position_count++;
    }
    return true;
}