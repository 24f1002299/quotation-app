package com.quotapp.api.dto;

import java.util.List;

/**
 * Generic paginated response wrapper for history and search lists.
 */
public record PageResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean isLast
) {
    public static <T> PageResponse<T> of(List<T> content, int page, int size, long totalElements) {
        int totalPages = size > 0 ? (int) Math.ceil((double) totalElements / size) : 0;
        boolean isLast = page >= totalPages - 1;
        return new PageResponse<>(content, page, size, totalElements, totalPages, isLast);
    }
}
