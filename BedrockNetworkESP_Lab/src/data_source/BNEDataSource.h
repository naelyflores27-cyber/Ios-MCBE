#ifndef BNE_DATA_SOURCE_H
#define BNE_DATA_SOURCE_H

#include "../entity/BNEEntityTracker.h"

typedef enum {
    BNE_SOURCE_STATE_UNKNOWN = 0,
    BNE_SOURCE_STATE_READY,
    BNE_SOURCE_STATE_CONNECTED,
    BNE_SOURCE_STATE_FAILED,
    BNE_SOURCE_STATE_STOPPED
} BNEDataSourceState;

typedef struct {
    bool observes_transport;
    bool decodes_bedrock_packets;
    bool emits_entity_events;
    bool emits_positions;
    bool emits_camera_state;
} BNEDataSourceCapabilities;

typedef void (*BNEObservationHandler)(void *handler_context,
                                      const BNEObservation *observation);

typedef struct {
    bool (*initialize)(void *context,
                       BNEObservationHandler handler,
                       void *handler_context);
    bool (*start)(void *context);
    BNEDataSourceState (*state)(void *context);
    BNEDataSourceCapabilities (*capabilities)(void *context);
    const char *(*last_error)(void *context);
    void (*shutdown)(void *context);
} BNEDataSourceVTable;

typedef struct {
    void *context;
    const BNEDataSourceVTable *vtable;
    BNEObservationSource observation_source;
} BNEDataSource;

#endif