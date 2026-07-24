-- Single source of truth for release/update settings.
--
-- Public GitHub Releases endpoint used by the on-device updater. Users can
-- still override this value from Word Wise > Updates on the device.
return {
    version = "2026.07.1-rc1.3.0",
    plugin_id = "wordwise.koplugin",
    asset_basename = "wordwise.koplugin",
    default_repository = "trigon1998/wordwise.koplugin-custom",
    user_agent = "KOReader-WordWise",
    max_archive_bytes = 8 * 1024 * 1024,
    max_file_bytes = 2 * 1024 * 1024,
}
