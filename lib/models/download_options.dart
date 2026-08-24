class DownloadOptions {
  final bool autoSaveToGallery;
  final bool removeCacheAfterGallery;

  const DownloadOptions({
    this.autoSaveToGallery = true,
    this.removeCacheAfterGallery = false,
  });
}
