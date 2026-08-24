-- Single source of truth for release/update settings.
--
-- Public GitHub Releases endpoint used by the on-device updater. Users can
-- still override this value from Word Wise > Updates on the device.
return {
    version = "2026.07.1-rc1.4.1",
    plugin_id = "wordwise.koplugin",
    asset_basename = "wordwise.koplugin",
    data_asset_basename = "WordWise_Databases_",
    default_repository = "trigon1998/wordwise.koplugin-custom",
    user_agent = "KOReader-WordWise",
    max_archive_bytes = 8 * 1024 * 1024,
    max_file_bytes = 2 * 1024 * 1024,
    max_data_archive_bytes = 32 * 1024 * 1024,
    max_data_unpacked_bytes = 64 * 1024 * 1024,
    max_database_bytes = 16 * 1024 * 1024,
    max_data_metadata_bytes = 256 * 1024,
}
