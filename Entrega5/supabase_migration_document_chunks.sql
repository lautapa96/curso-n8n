drop table if exists document_chunks;

create extension if not exists vector;

create table document_chunks (
    id bigserial primary key,
    content text not null,
    metadata jsonb,
    embedding vector(768)
);

create index document_chunks_embedding_idx
    on document_chunks
    using ivfflat (embedding vector_cosine_ops)
    with (lists = 100);

create or replace function match_document_chunks (
    query_embedding vector(768),
    match_count int default 3,
    filter jsonb default '{}'
)
returns table (
    id bigint,
    content text,
    metadata jsonb,
    similarity float
)
language plpgsql
as $$
begin
    return query
    select
        document_chunks.id,
        document_chunks.content,
        document_chunks.metadata,
        1 - (document_chunks.embedding <=> query_embedding) as similarity
    from document_chunks
    where document_chunks.metadata @> filter
    order by document_chunks.embedding <=> query_embedding
    limit match_count;
end;
$$;