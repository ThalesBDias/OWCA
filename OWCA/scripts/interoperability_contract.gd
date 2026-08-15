class_name InteroperabilityContract
extends RefCounted

## Shared mechanics for OWCA's public regiment/character JSON boundary.
##
## Format-specific persistence classes still own their envelope and state
## migrations. This service centralizes only the rules that must remain equal
## across every interoperable OWCA file: public schema compatibility, producer
## metadata, extension namespaces, and safe copies of calculated preview data.

const SCHEMA_VERSION := "1.3.0"
const SUPPORTED_SCHEMA_MAJOR := 1
const EXTENSION_KEY_PATTERN := "^[A-Za-z0-9][A-Za-z0-9.-]+/[A-Za-z0-9][A-Za-z0-9._-]*$"


## Legacy pre-v0.5.1 files omit schema_version. A declared version must have a
## supported major number; minor/patch additions remain forward-compatible.
static func supports_schema_version(value: Variant) -> bool:
	if value == null or str(value).strip_edges().is_empty():
		return true
	var version_text := str(value).strip_edges()
	var parts := version_text.split(".", false)
	if parts.size() != 3:
		return false
	var numeric_part := RegEx.new()
	if numeric_part.compile("^[0-9]+$") != OK:
		return false
	for part in parts:
		if numeric_part.search(part) == null:
			return false
	return int(parts[0]) == SUPPORTED_SCHEMA_MAJOR


## External data must be an object whose first-level keys are namespaced as
## owner/area. OWCA treats all values below those keys as opaque JSON.
static func extensions_are_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var key_pattern := RegEx.new()
	if key_pattern.compile(EXTENSION_KEY_PATTERN) != OK:
		return false
	for key: Variant in value:
		if key_pattern.search(str(key)) == null:
			return false
	return true


static func build_producer() -> Dictionary:
	return {
		"name": str(ProjectSettings.get_setting("application/config/name", "OWCA")),
		"version": str(ProjectSettings.get_setting("application/config/version", "unknown"))
	}


static func copy_dictionary(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func copy_array(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	return (value as Array).duplicate(true) if value is Array else []


## Full unresolved choice definitions can be large and contain current rules.
## A preview needs only stable identity, display context, and cardinality.
static func summarize_unresolved(choices: Array, default_scope: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in choices:
		if not value is Dictionary:
			continue
		var choice := value as Dictionary
		output.append({
			"id": str(choice.get("id", "")),
			"prompt": str(choice.get("prompt", "")),
			"scope": str(choice.get("scope", default_scope)),
			"minimum": int(choice.get("minimum", 1)),
			"maximum": int(choice.get("maximum", 1))
		})
	return output
