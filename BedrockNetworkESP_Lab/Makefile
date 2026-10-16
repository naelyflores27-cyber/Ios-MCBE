CC ?= clang
CFLAGS ?= -std=c11 -Wall -Wextra -Werror
LDLIBS ?= -lm
BUILD := build
ENTITY := src/entity/BNEEntityTracker.c
PROJECTION := src/projection/BNEProjection.c

.PHONY: test python-test clean

test: $(BUILD)/test_entity_tracker $(BUILD)/test_projection $(BUILD)/test_fixture_pipeline $(BUILD)/test_snapshot_provider python-test
	$(BUILD)/test_entity_tracker
	$(BUILD)/test_projection
	$(BUILD)/test_fixture_pipeline
	$(BUILD)/test_snapshot_provider

python-test:
	python3 -m unittest discover -s tests/package -p 'test_*.py' -v

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/test_entity_tracker: $(ENTITY) tests/unit/test_entity_tracker.c | $(BUILD)
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/test_projection: $(PROJECTION) tests/unit/test_projection.c | $(BUILD)
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/test_fixture_pipeline: $(ENTITY) $(PROJECTION) tests/integration/test_fixture_pipeline.c | $(BUILD)
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@

$(BUILD)/test_snapshot_provider: $(ENTITY) src/entity/BNEEntitySnapshotProvider.c tests/unit/test_snapshot_provider.c | $(BUILD)
	$(CC) $(CFLAGS) -pthread $^ $(LDLIBS) -o $@

clean:
	rm -rf $(BUILD)