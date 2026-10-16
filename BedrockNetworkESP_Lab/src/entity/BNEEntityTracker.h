#ifndef BNE_ENTITY_TRACKER_H
#define BNE_ENTITY_TRACKER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BNE_MAX_ENTITIES 256
#define BNE_SESSION_ID_CAPACITY 64
#define BNE_TYPE_ID_CAPACITY 96

typedef enum {
    BNE_EVENT_SPAWN = 1,
    BNE_EVENT_UPDATE,
    BNE_EVENT_REMOVE,
    BNE_EVENT_SESSION_RESET
} BNEEventType;

typedef enum {
    BNE_SOURCE_TEST_FIXTURE = 1,
    BNE_SOURCE_PASSIVE_CAPTURE,
    BNE_SOURCE_PROTOCOL_DECODER,
    BNE_SOURCE_IN_PROCESS,
    BNE_SOURCE_SERVER_GROUND_TRUTH
} BNEObservationSource;

typedef struct {
    BNEEventType type;
    BNEObservationSource source;
    char session_id[BNE_SESSION_ID_CAPACITY];
    uint64_t runtime_id;
    char entity_type_id[BNE_TYPE_ID_CAPACITY];
    uint64_t observed_at_ms;
    uint64_t sequence;
    bool has_position;
    double position[3];
    bool has_rotation;
    double rotation[3];
} BNEObservation;

typedef struct {
    uint64_t runtime_id;
    char entity_type_id[BNE_TYPE_ID_CAPACITY];
    double position[3];
    double rotation[3];
    bool has_position;
    bool has_rotation;
    BNEObservationSource position_source;
    BNEObservationSource rotation_source;
    uint64_t position_observed_at_ms;
    uint64_t last_observed_at_ms;
    uint64_t last_sequence;
    uint64_t session_generation;
    BNEObservationSource source;
} BNEEntitySnapshot;

typedef struct {
    uint64_t event_count;
    uint64_t update_count;
    uint64_t removal_count;
    uint64_t rejected_count;
    size_t tracked_count;
    size_t valid_position_count;
    size_t incomplete_count;
    size_t stale_count;
} BNETrackerDiagnostics;

typedef struct {
    BNEEntitySnapshot entities[BNE_MAX_ENTITIES];
    size_t count;
    uint64_t session_generation;
    uint64_t published_at_ms;
    BNETrackerDiagnostics diagnostics;
} BNESnapshot;

typedef struct {
    BNEEntitySnapshot entities[BNE_MAX_ENTITIES];
    size_t count;
    char session_id[BNE_SESSION_ID_CAPACITY];
    uint64_t session_generation;
    BNETrackerDiagnostics diagnostics;
} BNEEntityTracker;

typedef enum {
    BNE_APPLY_REJECTED = 0,
    BNE_APPLY_IGNORED,
    BNE_APPLY_ACCEPTED
} BNEApplyResult;

void bne_tracker_init(BNEEntityTracker *tracker);
BNEApplyResult bne_tracker_apply(BNEEntityTracker *tracker,
                                 const BNEObservation *observation);
bool bne_tracker_snapshot(const BNEEntityTracker *tracker,
                          uint64_t now_ms,
                          uint64_t max_age_ms,
                          BNESnapshot *snapshot);

#endif