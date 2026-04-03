package inframetrics

import (
	"testing"

	v3 "github.com/SigNoz/signoz/pkg/query-service/model/v3"
)

func TestHostsTableListQueryMemoryTemporality(t *testing.T) {
	memoryUsedQuery, ok := HostsTableListQuery.CompositeQuery.BuilderQueries["C"]
	if !ok {
		t.Fatal("expected memory used query C to exist")
	}

	memoryTotalQuery, ok := HostsTableListQuery.CompositeQuery.BuilderQueries["D"]
	if !ok {
		t.Fatal("expected memory total query D to exist")
	}

	memoryFormulaQuery, ok := HostsTableListQuery.CompositeQuery.BuilderQueries["F2"]
	if !ok {
		t.Fatal("expected memory formula query F2 to exist")
	}

	if memoryUsedQuery.AggregateAttribute.Key != metricNamesForHosts["memory"] {
		t.Fatalf("expected query C metric %q, got %q", metricNamesForHosts["memory"], memoryUsedQuery.AggregateAttribute.Key)
	}

	if memoryTotalQuery.AggregateAttribute.Key != metricNamesForHosts["memory"] {
		t.Fatalf("expected query D metric %q, got %q", metricNamesForHosts["memory"], memoryTotalQuery.AggregateAttribute.Key)
	}

	if memoryUsedQuery.Temporality != v3.Unspecified {
		t.Fatalf("expected query C temporality %q, got %q", v3.Unspecified, memoryUsedQuery.Temporality)
	}

	if memoryTotalQuery.Temporality != v3.Unspecified {
		t.Fatalf("expected query D temporality %q, got %q", v3.Unspecified, memoryTotalQuery.Temporality)
	}

	if memoryFormulaQuery.Expression != "C/D" {
		t.Fatalf("expected query F2 expression %q, got %q", "C/D", memoryFormulaQuery.Expression)
	}
}
