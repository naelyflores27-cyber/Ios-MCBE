#include "BNEEntitySnapshotProvider.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static pthread_mutex_t s_tracker_lock = PTHREAD_MUTEX_INITIALIZER;
static BNEEntityTracker s_tracker;
static bool s_tracker_initialized;

static size_t bne_bounded_length(const char *text, size_t capacity) {
    size_t length = 0;
    while (length < capacity && text[length] != '\0') length++;
    return length;
}

static void bne_ensure_tracker_initialized(void) {
    if (s_tracker_initialized) return;
    bne_tracker_init(&s_tracker);
    s_tracker_initialized = true;
}

bool bne_entity_snapshot_provider_reset_session(const char *session_id) {
    if (!session_id || session_id[0] == '\0' ||
        bne_bounded_length(session_id, BNE_SESSION_ID_CAPACITY) >=
            BNE_SESSION_ID_CAPACITY) {
        return false;
    }
    pthread_mutex_lock(&s_tracker_lock);
    bne_ensure_tracker_initialized();
    BNEObservation observation = {0};
    observation.type = BNE_EVENT_SESSION_RESET;
    memcpy(observation.session_id, session_id, strlen(session_id) + 1);
    bool accepted = bne_tracker_apply(&s_tracker, &observation) == BNE_APPLY_ACCEPTED;
    pthread_mutex_unlock(&s_tracker_lock);
    return accepted;
}

BNEApplyResult bne_entity_snapshot_provider_apply(const BNEObservation *observation) {
    if (!observation) return BNE_APPLY_REJECTED;
    pthread_mutex_lock(&s_tracker_lock);
    bne_ensure_tracker_initialized();
    BNEApplyResult result = bne_tracker_apply(&s_tracker, observation);
    pthread_mutex_unlock(&s_tracker_lock);
    return result;
}

bool bne_entity_snapshot_provider_copy(uint64_t now_ms,
                                       uint64_t max_age_ms,
                                       BNESnapshot *snapshot) {
    if (!snapshot) return false;
    pthread_mutex_lock(&s_tracker_lock);
    bne_ensure_tracker_initialized();
    bool copied = bne_tracker_snapshot(&s_tracker, now_ms, max_age_ms, snapshot);
    pthread_mutex_unlock(&s_tracker_lock);
    return copied;
}