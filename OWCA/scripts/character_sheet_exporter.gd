class_name CharacterSheetExporter
extends RefCounted

## Renders the OWCA sheet at 300 DPI and exports PDF plus PNG pages. Most
## characters use two pages; unusually large owned inventories gain loadout
## continuation pages instead of being silently truncated.


func export_pdf_and_png(path: String, state: CharacterState, calculation: Dictionary, host: Node) -> Dictionary:
	if host == null or not host.is_inside_tree():
		return { "error": ERR_UNCONFIGURED, "message": "Character-sheet exporter needs an active scene tree." }
	if not bool(calculation.get("valid", false)):
		return { "error": ERR_INVALID_DATA, "message": "Resolve all character errors and choices before exporting the sheet." }

	var pdf_path := path if path.to_lower().ends_with(".pdf") else path + ".pdf"
	var base_path := pdf_path.left(pdf_path.length() - 4)
	var images: Array[Image] = []
	var png_paths: Array[String] = []
	var layout_helper := PrintableCharacterSheet.new()
	var page_count := layout_helper.get_required_page_count(calculation, str(state.comrade.get("name", "")))
	layout_helper.free()
	for page in range(1, page_count + 1):
		var image := await _render_page(state, calculation, page, page_count, host)
		if image == null or image.is_empty():
			return { "error": ERR_CANT_CREATE, "message": "Could not render character-sheet page %d." % page }
		images.append(image)
		var png_path := "%s_page_%d.png" % [base_path, page]
		var png_error := image.save_png(png_path)
		if png_error != OK:
			return { "error": png_error, "message": "Could not save PNG page %d to %s." % [page, png_path] }
		png_paths.append(png_path)

	var pdf_result := PdfImageWriter.new().write(pdf_path, images)
	if int(pdf_result.get("error", ERR_CANT_CREATE)) != OK:
		return pdf_result
	pdf_result["png_paths"] = png_paths
	pdf_result["message"] = "Exported %d-page A4 PDF and PNG sheets to %s." % [page_count, pdf_path.get_base_dir()]
	return pdf_result


func _render_page(state: CharacterState, calculation: Dictionary, page: int, page_count: int, host: Node) -> Image:
	var viewport := SubViewport.new()
	viewport.name = "CharacterSheetRenderPage%d" % page
	viewport.size = PrintableCharacterSheet.PAGE_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(viewport)

	var sheet := PrintableCharacterSheet.new()
	viewport.add_child(sheet)
	sheet.configure(state, calculation, page, page_count)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	return image
