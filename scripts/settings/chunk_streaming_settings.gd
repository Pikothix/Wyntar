extends RefCounted
## Typed pre-ready snapshot of bounded chunk-streaming budgets.

var load_margin_chunks: int
var unload_margin_chunks: int
var chunks_created_per_frame: int
var profiling_enabled: bool
var max_chunk_processing_ms: float
var chunk_work_quantum_cells: int
var max_tile_cells_per_frame: int


static func capture(source):
	var settings = new()
	settings.load_margin_chunks = source.load_margin_chunks
	settings.unload_margin_chunks = source.unload_margin_chunks
	settings.chunks_created_per_frame = source.chunks_created_per_frame
	settings.profiling_enabled = source.chunk_profiling_enabled
	settings.max_chunk_processing_ms = source.max_chunk_processing_ms
	settings.chunk_work_quantum_cells = source.chunk_work_quantum_cells
	settings.max_tile_cells_per_frame = source.max_tile_cells_per_frame
	return settings


func apply_to(renderer) -> void:
	renderer.load_margin_chunks = load_margin_chunks
	renderer.unload_margin_chunks = unload_margin_chunks
	renderer.chunks_created_per_frame = chunks_created_per_frame
	renderer.profiling_enabled = profiling_enabled
	renderer.max_chunk_processing_ms = max_chunk_processing_ms
	renderer.chunk_work_quantum_cells = chunk_work_quantum_cells
	renderer.max_tile_cells_per_frame = max_tile_cells_per_frame
