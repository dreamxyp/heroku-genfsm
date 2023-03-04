REBAR ?= $(shell which rebar 2>/dev/null || which ./rebar)
REBAR_FLAGS ?=

Erl ?= erl
ErlC ?= erlc

# app name
App_Name = egeoip

Root=./../..
Root_Ebin=$(Root)/ebin
Curr_Ebin=$(Root_Ebin)/$(App_Name)
Curr_Root=$(Root)/deps/$(App_Name)

all: compile

compile:
	@mkdir -p $(Curr_Ebin)
	@$(Erl) -pa $(Curr_Ebin) -pa $(Root_Ebin)/*/ -pa $(Root)/deps/*/ -noshell -make -j 10
	@cp -r $(Curr_Root)/src/$(App_Name).app.src $(Curr_Ebin)/$(App_Name).app
	@echo ">>\033[32m 编译$(App_Name) 完成 \033[0m "
	@# $(REBAR) compile $(REBAR_FLAGS)

doc:
	@# $(REBAR) doc $(REBAR_FLAGS)

test: compile
	@# $(REBAR) eunit $(REBAR_FLAGS)

clean:
	@rm -rf $(Curr_Ebin)/*.beam
	@rm -rf $(Curr_Ebin)/*.app
	@rm -rf $(Curr_Ebin)/erl_crash.dump
	@rm -rf erl_crash.dump
	@echo ">>\033[91m 清理$(App_Name) 完成 \033[0m "
	@# $(REBAR) clean $(REBAR_FLAGS)

clean_plt:
	@# @rm -f _test/dialyzer_plt

build_plt: build-plt

build-plt:
	@# @ [ -d _test ] || mkdir _test
	@# $(REBAR) build-plt $(REBAR_FLAGS)

dialyzer:
	@# $(REBAR) dialyze $(REBAR_FLAGS)

