package dev.sunbirdrc.elastic;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.jayway.jsonpath.DocumentContext;
import com.jayway.jsonpath.JsonPath;
import dev.sunbirdrc.pojos.Filter;
import dev.sunbirdrc.pojos.FilterOperators;
import dev.sunbirdrc.pojos.SearchQuery;
import dev.sunbirdrc.registry.middleware.util.Constants;
import dev.sunbirdrc.registry.middleware.util.JSONUtil;
import java.io.IOException;
import java.net.ConnectException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;
import org.apache.http.HttpHost;
import org.elasticsearch.action.admin.indices.create.CreateIndexRequest;
import org.elasticsearch.action.admin.indices.create.CreateIndexResponse;
import org.elasticsearch.action.get.GetRequest;
import org.elasticsearch.action.get.GetResponse;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.action.index.IndexResponse;
import org.elasticsearch.action.search.SearchRequest;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.action.update.UpdateRequest;
import org.elasticsearch.action.update.UpdateResponse;
import org.elasticsearch.client.Request;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.Response;
import org.elasticsearch.client.RestClient;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.index.query.BoolQueryBuilder;
import org.elasticsearch.index.query.QueryBuilders;
import org.elasticsearch.rest.RestStatus;
import org.elasticsearch.search.SearchHit;
import org.elasticsearch.search.builder.SearchSourceBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Retryable;

import javax.annotation.PreDestroy;

public class ElasticServiceImpl implements IElasticService {
    private static final Map<String, Set<String>> indexWiseExcludeFields = new ConcurrentHashMap<>();
    private static final Map<String, RestHighLevelClient> esClient = new ConcurrentHashMap<>();
    private static final Logger logger = LoggerFactory.getLogger(ElasticServiceImpl.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    /** Pattern to sanitize Elasticsearch query string special characters */
    private static final Pattern ES_QUERY_SPECIAL_CHARS = Pattern.compile("[+\\-=&|><!(){}\\[\\]^\"~*?:\\\\/]");

    private static String connectionInfo;
    private static String searchType;

    public void setConnectionInfo(String connection) {
        connectionInfo = connection;
    }

    public void setType(String type) {
        searchType = type;
    }

    /**
     * This method runs when the application is started in order to add all the indices to the elastic search
     */
    public void init(Set<String> indices, Map<String, Set<String>> excludeFields) throws RuntimeException {
        indexWiseExcludeFields.putAll(excludeFields);
        indices.forEach(index -> {
            try {
                addIndex(index.toLowerCase(), searchType);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        });
    }

    @PreDestroy
    public void cleanup() {
        esClient.forEach((index, client) -> {
            try {
                client.close();
            } catch (IOException e) {
                logger.error("Error closing ES client for index {}", index, e);
            }
        });
        esClient.clear();
    }

    private static void createClient(String indexName, String connectionInfo) {
        esClient.computeIfAbsent(indexName, key -> {
            Map<String, Integer> hostPort = new HashMap<>();
            for (String info : connectionInfo.split(",")) {
                String[] parts = info.split(":");
                hostPort.put(parts[0], Integer.valueOf(parts[1]));
            }
            List<HttpHost> httpHosts = new ArrayList<>();
            for (String host : hostPort.keySet()) {
                httpHosts.add(new HttpHost(host, hostPort.get(host)));
            }
            return new RestHighLevelClient(
                    RestClient.builder(httpHosts.toArray(new HttpHost[0])));
        });
    }

    private static RestHighLevelClient getClient(String indexName) {
        logger.debug("connection info: index:{} connectioninfo:{}", indexName, connectionInfo);
        createClient(indexName, connectionInfo);
        return esClient.get(indexName);
    }

    @Retryable(value = {IOException.class, ConnectException.class}, maxAttemptsExpression = "#{${service.retry.maxAttempts}}",
            backoff = @Backoff(delayExpression = "#{${service.retry.backoff.delay}}"))
    public static boolean addIndex(String indexName, String documentType) throws IOException {
        boolean response = false;
        RestHighLevelClient client = getClient(indexName);
        if (!isIndexExists(indexName)) {
            CreateIndexRequest createRequest = new CreateIndexRequest(indexName);
            CreateIndexResponse createIndexResponse = client.indices().create(createRequest, RequestOptions.DEFAULT);
            response = createIndexResponse.isAcknowledged();
        }
        return response;
    }

    public static boolean isIndexExists(String indexName) {
        Response response;
        try {
            response = getClient(indexName).getLowLevelClient().performRequest(new Request("HEAD", "/" + indexName));
            return (200 == response.getStatusLine().getStatusCode());
        } catch (IOException e) {
            logger.warn("Failed to check if index {} exists", indexName, e);
            return false;
        }
    }

    @Override
    public RestStatus addEntity(String index, String entityId, JsonNode inputEntity) {
        logger.debug("addEntity starts with index {} and entityId {}", index, entityId);
        try {
            DocumentContext doc = getDocumentContextAfterRemovingExcludedFields(index, inputEntity);
            JsonNode filteredNode = JSONUtil.convertStringJsonNode(doc.jsonString());
            Map<String, Object> inputMap = JSONUtil.convertJsonNodeToMap(filteredNode);
            IndexResponse response = getClient(index).index(new IndexRequest(index, searchType, entityId).source(inputMap), RequestOptions.DEFAULT);
            return response.status();
        } catch (IOException e) {
            logger.error("Exception in adding record to ElasticSearch", e);
            return RestStatus.INTERNAL_SERVER_ERROR;
        }
    }

    @Override
    @Retryable(value = {IOException.class, ConnectException.class}, maxAttemptsExpression = "#{${service.retry.maxAttempts}}",
            backoff = @Backoff(delayExpression = "#{${service.retry.backoff.delay}}"))
    public Map<String, Object> readEntity(String index, String osid) throws IOException {
        logger.debug("readEntity starts with index {} and entityId {}", index, osid);
        GetResponse response = getClient(index).get(new GetRequest(index, searchType, osid), RequestOptions.DEFAULT);
        return response.getSourceAsMap();
    }

    @Override
    public RestStatus updateEntity(String index, String osid, JsonNode inputEntity) {
        logger.debug("updateEntity starts with index {} and entityId {}", index, osid);
        try {
            DocumentContext doc = getDocumentContextAfterRemovingExcludedFields(index, inputEntity);
            JsonNode filteredNode = JSONUtil.convertStringJsonNode(doc.jsonString());
            Map<String, Object> inputMap = JSONUtil.convertJsonNodeToMap(filteredNode);
            logger.debug("updateEntity inputMap {}", inputMap);
            UpdateResponse response = getClient(index.toLowerCase()).update(new UpdateRequest(index.toLowerCase(), searchType, osid).doc(inputMap), RequestOptions.DEFAULT);
            return response.status();
        } catch (IOException e) {
            logger.error("Exception in updating a record to ElasticSearch", e);
            return RestStatus.INTERNAL_SERVER_ERROR;
        }
    }

    private DocumentContext getDocumentContextAfterRemovingExcludedFields(String index, JsonNode inputEntity) throws com.fasterxml.jackson.core.JsonProcessingException {
        DocumentContext doc = JsonPath.parse(JSONUtil.convertObjectJsonString(inputEntity));
        Set<String> excludeFields = indexWiseExcludeFields.get(index);
        if (excludeFields != null) {
            for (String jsonPath : excludeFields) {
                try {
                    doc.delete(jsonPath);
                } catch (Exception e) {
                    logger.debug("Path not found {} {}", jsonPath, e.getMessage());
                }
            }
        }
        return doc;
    }

    @Override
    public RestStatus deleteEntity(String index, String osid) {
        try {
            String indexL = index.toLowerCase();
            Map<String, Object> readMap = readEntity(indexL, osid);
            if (readMap == null) {
                return RestStatus.NOT_FOUND;
            }
            readMap.put(Constants.STATUS_KEYWORD, Constants.STATUS_INACTIVE);
            UpdateResponse response = getClient(indexL).update(new UpdateRequest(indexL, searchType, osid).doc(readMap), RequestOptions.DEFAULT);
            return response.status();
        } catch (NullPointerException | IOException e) {
            logger.error("Exception in deleteEntity for index {} osid {}", index, osid, e);
            return RestStatus.NOT_FOUND;
        }
    }

    @Override
    @Retryable(value = {IOException.class, ConnectException.class}, maxAttemptsExpression = "#{${service.retry.maxAttempts}}",
            backoff = @Backoff(delayExpression = "#{${service.retry.backoff.delay}}"))
    public JsonNode search(String index, SearchQuery searchQuery) throws IOException {
        BoolQueryBuilder query = buildQuery(searchQuery);

        SearchSourceBuilder sourceBuilder = new SearchSourceBuilder()
                .query(query)
                .size(searchQuery.getLimit())
                .from(searchQuery.getOffset());
        SearchRequest searchRequest = new SearchRequest(index).source(sourceBuilder);
        ArrayNode resultArray = JsonNodeFactory.instance.arrayNode();
        SearchResponse searchResponse = getClient(index).search(searchRequest, RequestOptions.DEFAULT);
        for (SearchHit hit : searchResponse.getHits()) {
            JsonNode node = objectMapper.readValue(hit.getSourceAsString(), JsonNode.class);
            if (node.get("_status") == null || node.get("_status").asBoolean()) {
                resultArray.add(node);
            }
        }
        logger.debug("Total search records found {}", resultArray.size());

        return resultArray;
    }

    /**
     * Sanitize user input for Elasticsearch query string to prevent injection
     */
    private String sanitizeQueryString(String input) {
        if (input == null) {
            return "";
        }
        return ES_QUERY_SPECIAL_CHARS.matcher(input).replaceAll("\\\\$0");
    }

    private BoolQueryBuilder buildQuery(SearchQuery searchQuery) {
        List<Filter> filters = searchQuery.getFilters();
        BoolQueryBuilder query = QueryBuilders.boolQuery();

        for (Filter filter : filters) {
            String field = filter.getProperty();
            Object value = filter.getValue();
            FilterOperators operator = filter.getOperator();
            String path = filter.getPath();

            if (path != null) {
                field = path + "." + field;
            }
            switch (operator) {
            case eq:
                query = query.must(QueryBuilders.matchPhraseQuery(field, value));
                break;
            case neq:
                query = query.mustNot(QueryBuilders.matchPhraseQuery(field, value));
                break;
            case gt:
                query = query.must(QueryBuilders.rangeQuery(field).gt(value));
                break;
            case lt:
                query = query.must(QueryBuilders.rangeQuery(field).lt(value));
                break;
            case gte:
                query = query.must(QueryBuilders.rangeQuery(field).gte(value));
                break;
            case lte:
                query = query.must(QueryBuilders.rangeQuery(field).lte(value));
                break;
            case between:
                List<Object> objects = (List<Object>) value;
                query = query
                        .must(QueryBuilders.rangeQuery(field).from(objects.get(0)).to(objects.get(objects.size() - 1)));
                break;
            case or:
                List<Object> values = (List<Object>) value;
                query = query.must(QueryBuilders.termsQuery(String.format("%s.keyword", field), values));
                break;
            case contains:
                query = query.must(QueryBuilders.matchPhraseQuery(field, value));
                break;
            case startsWith:
                query = query.must(QueryBuilders.matchPhrasePrefixQuery(field, value.toString()));
                break;
            case endsWith:
                query = query.must(QueryBuilders.wildcardQuery(field, "*" + value));
                break;
            case notContains:
                query = query.mustNot(QueryBuilders.matchPhraseQuery(field, value));
                break;
            case notStartsWith:
                query = query.mustNot(QueryBuilders.matchPhrasePrefixQuery(field, value.toString()));
                break;
            case notEndsWith:
                query = query.mustNot(QueryBuilders.wildcardQuery(field, "*" + value));
                break;
            case queryString:
                query = query.must(QueryBuilders.queryStringQuery(sanitizeQueryString(value.toString())));
                break;
            default:
                query = query.must(QueryBuilders.matchQuery(field, value));
                break;
            }
        }

        return query;
    }

}
