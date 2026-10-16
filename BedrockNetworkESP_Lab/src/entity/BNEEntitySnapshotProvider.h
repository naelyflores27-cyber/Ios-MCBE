#ifndef BNE_ENTITY_SNAPSHOT_PROVIDER_H
#define BNE_ENTITY_SNAPSHOT_PROVIDER_H

#include "BNEEntityTracker.h"

bool bne_entity_snapshot_provider_reset_session(const char *session_id);
BNEApplyResult bne_entity_snapshot_provider_apply(const BNEObservation *observation);
bool bne_entity_snapshot_provider_copy(uint64_t now_ms,
                                       uint64_t max_age_ms,
                                       BNESnapshot *snapshot);

#endif