package org.sunbird.akka.core;

import akka.actor.ActorRef;
import akka.actor.ActorSelection;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Caches the operation and its corresponding ActorRef
 */
public class ActorCache {
    private static final Logger logger = LoggerFactory.getLogger(ActorCache.class);

    private final Map<String, ActorRef> routingMap = new ConcurrentHashMap<>();
    private final Map<String, ActorSelection> remoteRoutingMap = new ConcurrentHashMap<>();

    /** Holder pattern for thread-safe lazy initialization */
    private static class Holder {
        private static final ActorCache INSTANCE = new ActorCache();
    }

    /**
     * Disallow external instantiation
     */
    private ActorCache() {}

    /**
     * Externally used to get an instance of this class
     * @return the singleton ActorCache instance
     */
    public static ActorCache instance() {
        return Holder.INSTANCE;
    }

    /**
     * Add the ActorRef to the cache
     */
    public void add(String absName, ActorRef actor) {
        routingMap.put(absName, actor);
    }

    /**
     * Add the ActorSelection to the cache
     */
    public void add(String absName, ActorSelection actor) {
        remoteRoutingMap.put(absName, actor);
    }

    public ActorRef get(String simpleName) {
        return routingMap.get(simpleName);
    }

    public ActorSelection getRemote(String simpleName) {
        return remoteRoutingMap.get(simpleName);
    }

    protected void print() {
        routingMap.forEach((k, v) -> logger.info("{} -> {}", k, v));
        remoteRoutingMap.forEach((k, v) -> logger.info("{} -> {}", k, v));
    }
}
