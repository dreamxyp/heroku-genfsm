#!/bin/sh

#cd `dirname $0`
#exec erl +K true -pa $PWD/ebin $PWD/deps/*/ebin -boot start_sasl -s genfsm

erl +K true -pa ./ebin ./ebin/*/ -boot start_sasl -s genfsm start
