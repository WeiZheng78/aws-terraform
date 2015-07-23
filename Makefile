CWD := $(shell pwd)
PROFILE_NAME := coreos-cluster
PROFILE := "profile $(PROFILE_NAME)"
SRC := $(CWD)/coreos-cluster
BUILD := $(CWD)/build
SCRIPTS := $(CWD)/scripts
# Terraform dirs and var files
TF_COMMON := $(BUILD)/tfcommon
KEY_VARS := $(TF_COMMON)/keys.tfvars
VPC_VARS_TF=$(TF_COMMON)/vpc-vars.tf
VPC_VARS := $(TF_COMMON)/vpc-vars.tfvars
R53_VARS := $(TF_COMMON)/route53-vars.tfvars
# Terraform commands
TF_PLAN := terraform plan --var-file=$(KEY_VARS)
TF_APPLY := terraform apply --var-file=$(KEY_VARS)
TF_REFRESH := terraform refresh --var-file=$(KEY_VARS)
TF_DESTROY_PLAN := terraform plan -destroy --var-file=$(KEY_VARS) --out=destroy.tfplan
TF_DESTROY_APPLY := terraform apply destroy.tfplan
TF_SHOW := terraform show
TF_DESTROY_PLAN_FILE := destroy.tfplan
# For get-ami.sh
COREOS_UPDATE_CHANNE=beta
AWS_ZONE=us-west-2
VM_TYPE=hvm

# Note the order of BUILD_SUBDIRS is significant, because there are dependences on destroy_all
BUILD_SUBDIRS :=  worker etcd s3 iam route53 vpc

# Get goals for sub-module
SUBGOALS := $(filter-out $(BUILD_SUBDIRS) all, $(MAKECMDGOALS))

# Get the sub-module name
GOAL := $(firstword $(MAKECMDGOALS))

# Get the sub-module dir
BUILD_SUBDIR := build/$(GOAL)

# Exports all above vars
export


all:
	$(MAKE) worker

# Copy sub-module dir to build
$(BUILD_SUBDIR): | $(BUILD) build_subdir

build_subdir:
	cp -R $(SRC)/$(GOAL) $(BUILD)

# Create build dir and copy tfcommon to build
$(BUILD): init_build

init_build: 
	mkdir -p $(BUILD)
	# Copy shared terraform files
	cp -Rf  $(SRC)/tfcommon $(BUILD)
	# Generate default AMI id
	$(SCRIPTS)/get-ami.sh >> $(TF_COMMON)/override.tf
	# Generate keys.tfvars from AWS credentials
	echo aws_access_key = \"$(shell $(SCRIPTS)/read_cfg.sh $(HOME)/.aws/credentials $(PROFILE_NAME) aws_access_key_id)\" > $(KEY_VARS)
	echo aws_secret_key = \"$(shell $(SCRIPTS)/read_cfg.sh $(HOME)/.aws/credentials $(PROFILE_NAME) aws_secret_access_key)\" >> $(KEY_VARS)	
	echo aws_region = \"$(shell $(SCRIPTS)/read_cfg.sh $(HOME)/.aws/config $(PROFILE) region)\" >> $(KEY_VARS)

show_all:
	cd build; for dir in $(BUILD_SUBDIRS); do \
        test -d $$dir && $(MAKE) -C $$dir -i show ; \
        exit 0; \
    done

clean clean_all:
	echo Use \"make destroy_all\" to destroy ALL resources

destroy_all:
	cd build; for dir in $(BUILD_SUBDIRS); do \
        test -d $$dir && $(MAKE) -C $$dir destroy ; \
    done
	rm -rf $(BUILD)

vpc: | $(BUILD_SUBDIR)
	$(MAKE) -C $(BUILD)/vpc $(SUBGOALS)

# This goal is needed because some other goals dependents on $(VPC_VARS)
$(VPC_VARS):
	$(MAKE) vpc apply

iam: | $(BUILD_SUBDIR)
	$(MAKE) -C $(BUILD_SUBDIR) $(SUBGOALS)

s3: | $(BUILD_SUBDIR)
	$(MAKE) -C $(BUILD_SUBDIR) $(SUBGOALS)

route53: | $(VPC_VARS) $(BUILD_SUBDIR)
	$(MAKE) -C $(BUILD_SUBDIR) $(SUBGOALS)

# This goal is needed because some other goals dependents on $(R53_VARS)
$(R53_VARS):
	$(MAKE) route53 apply

etcd: | $(BUILD_SUBDIR) $(VPC_VARS)
	$(MAKE) s3
	$(MAKE) iam
	$(MAKE) -C $(BUILD_SUBDIR) $(SUBGOALS)

worker: | $(BUILD_SUBDIR) $(VPC_VARS)
	$(MAKE) etcd
	$(MAKE) -C $(BUILD_SUBDIR) $(SUBGOALS)

# Terraform Targets
apply destroy destroy_plan init plan refresh show :
	# Goals for sub-module $(MAKECMDGOALS)

.PHONY: $(BUILD) $(BUILD_SUBDIR)
.PHONY: init_build build_subdir show_all destroy_all all
.PHONY: pall lan apply destroy_plan destroy refresh show init