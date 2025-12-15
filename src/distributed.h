#ifndef DISTRIBUTED_H
#define DISTRIBUTED_H

#include <stdint.h>
#include <stdbool.h>

// Master server functions
int master_start(const char *port, const char *url, 
                 uint64_t threads, uint64_t connections, 
                 uint64_t duration, const char *script);

// Worker client functions
int worker_connect(const char *server_list);

// Message types for communication
typedef enum {
    MSG_CONFIG = 1,
    MSG_START,
    MSG_STATS,
    MSG_COMPLETE,
    MSG_ERROR
} message_type;

// Configuration message structure
typedef struct {
    message_type type;
    char url[256];
    uint64_t threads;
    uint64_t connections;
    uint64_t duration;
    char script[256];
} config_message;

// Statistics message structure
typedef struct {
    message_type type;
    uint64_t complete;
    uint64_t bytes;
    uint64_t errors_connect;
    uint64_t errors_read;
    uint64_t errors_write;
    uint64_t errors_timeout;
    uint64_t errors_status;
    double req_per_s;
    double bytes_per_s;
    uint64_t latency_avg;
    uint64_t latency_stdev;
    uint64_t latency_max;
} stats_message;

// Aggregated results structure
typedef struct {
    uint64_t total_complete;
    uint64_t total_bytes;
    uint64_t total_errors_connect;
    uint64_t total_errors_read;
    uint64_t total_errors_write;
    uint64_t total_errors_timeout;
    uint64_t total_errors_status;
    double avg_req_per_s;
    double avg_bytes_per_s;
    uint64_t avg_latency_avg;
    int client_count;
} aggregated_results;

#endif /* DISTRIBUTED_H */
