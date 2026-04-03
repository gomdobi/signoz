package inframetrics

import (
	"slices"
	"testing"

	v3 "github.com/SigNoz/signoz/pkg/query-service/model/v3"
)

func TestHostsTableListQueryMemoryTemporalities(t *testing.T) {
	tests := []struct {
		name        string
		queryName   string
		temporality v3.Temporality
		expression  string
		metricKey   string
	}{
		{
			name:        "memory cumulative used",
			queryName:   "C",
			temporality: v3.Cumulative,
			expression:  "C",
			metricKey:   metricNamesForHosts["memory"],
		},
		{
			name:        "memory cumulative total",
			queryName:   "D",
			temporality: v3.Cumulative,
			expression:  "D",
			metricKey:   metricNamesForHosts["memory"],
		},
		{
			name:        "memory unspecified used",
			queryName:   "H",
			temporality: v3.Unspecified,
			expression:  "H",
			metricKey:   metricNamesForHosts["memory"],
		},
		{
			name:        "memory unspecified total",
			queryName:   "I",
			temporality: v3.Unspecified,
			expression:  "I",
			metricKey:   metricNamesForHosts["memory"],
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			query, ok := HostsTableListQuery.CompositeQuery.BuilderQueries[tt.queryName]
			if !ok {
				t.Fatalf("expected query %s to exist", tt.queryName)
			}

			if query.AggregateAttribute.Key != tt.metricKey {
				t.Fatalf("expected query %s metric %q, got %q", tt.queryName, tt.metricKey, query.AggregateAttribute.Key)
			}

			if query.Temporality != tt.temporality {
				t.Fatalf("expected query %s temporality %q, got %q", tt.queryName, tt.temporality, query.Temporality)
			}

			if query.Expression != tt.expression {
				t.Fatalf("expected query %s expression %q, got %q", tt.queryName, tt.expression, query.Expression)
			}
		})
	}

	formulaTests := []struct {
		queryName  string
		expression string
	}{
		{queryName: "F2", expression: "C/D"},
		{queryName: "F2U", expression: "H/I"},
	}

	for _, tt := range formulaTests {
		query, ok := HostsTableListQuery.CompositeQuery.BuilderQueries[tt.queryName]
		if !ok {
			t.Fatalf("expected formula query %s to exist", tt.queryName)
		}
		if query.Expression != tt.expression {
			t.Fatalf("expected formula query %s expression %q, got %q", tt.queryName, tt.expression, query.Expression)
		}
	}
}

func TestHostsTopHostGroupsIncludeMemoryFallbackQueries(t *testing.T) {
	memoryQueries := queryNamesForTopHosts["memory"]

	for _, queryName := range []string{"C", "D", "F2", "H", "I", "F2U"} {
		if !slices.Contains(memoryQueries, queryName) {
			t.Fatalf("expected memory top host queries to include %s", queryName)
		}
	}
}
