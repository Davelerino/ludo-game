class_name HistoryEntry
extends PanelContainer
## ============================================================================
## HistoryEntry — Une ligne du panneau d'historique (%HistoryList dans
## history_panel.tscn). Composant d'affichage pur, alimenté par
## history_panel.gd via set_entry() — pas d'écoute GameEvents ici.
## ============================================================================

@onready var _header: Label = %EntryHeader
@onready var _detail: Label = %EntryDetail


## header_text : ex. "Rouge — 4 et 2". header_color : couleur du joueur
## (PlayerPalette.dark(id)). detail_text : résumé des coups/captures/bust,
## masqué si vide (ex. tour sans aucun coup possible reste informatif via le
## header seul, mais on garde aussi le texte "Aucun coup possible" en detail).
func set_entry(header_text: String, header_color: Color, detail_text: String) -> void:
	_header.text = header_text
	_header.add_theme_color_override("font_color", header_color)
	_detail.text = detail_text
	_detail.visible = detail_text != ""
