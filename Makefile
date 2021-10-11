.PHONY: help disable_default_catalog_source deploy_hco test_hco deploy_test

help:
	@echo "Run 'make deploy_test' to deploy and test HCO on target cluster"

deploy_test: disable_default_catalog_source deploy_hco test_hco

disable_default_catalog_source:
	hack/disable-default-catalog-source.sh

deploy_hco:
	hack/deploy-hco.sh

test_hco:
	hack/patch-hco-pre-test.sh
	hack/test-hco.sh

dump-state:
	./hack/dump-state.sh
