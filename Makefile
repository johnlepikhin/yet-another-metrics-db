
clean:
	rm out/*

out/collect-metrics:
	pp -P -I ./ -o out/collect-metrics collect-metrics.pl

out/dump-metrics:
	pp -P -I ./ -o out/dump-metrics dump-metrics.pl

out/register-metrics:
	pp -P -I ./ -o out/register-metrics register-metrics.pl

install: clean out/collect-metrics out/dump-metrics out/register-metrics
	install out/collect-metrics ~/bin/
	install out/dump-metrics ~/bin/
	install out/register-metrics ~/bin/
#	install -m 644 -D datainfo.ini ~/.metrics/config.ini
