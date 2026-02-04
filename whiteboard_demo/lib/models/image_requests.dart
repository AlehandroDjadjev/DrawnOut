/// Shared image pipeline contracts for script requests and research results.
library;

class ImagePlacement {
  final double x;
  final double y;
  final double width;
  final double height;
  final double? scale;

  ImagePlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.scale,
  });

  factory ImagePlacement.fromJson(Map<String, dynamic> json) {
    return ImagePlacement(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      scale: (json['scale'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      if (scale != null) 'scale': scale,
    };
  }
}

class ScriptImageRequest {
  final String id;
  final String prompt;
  final ImagePlacement? placement;
  final String? filenameHint;
  final String? style;

  ScriptImageRequest({
    required this.id,
    required this.prompt,
    this.placement,
    this.filenameHint,
    this.style,
  });

  factory ScriptImageRequest.fromJson(Map<String, dynamic> json) {
    return ScriptImageRequest(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      placement: json['placement'] != null
          ? ImagePlacement.fromJson(json['placement'] as Map<String, dynamic>)
          : null,
      filenameHint: json['filename_hint'] as String?,
      style: json['style'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prompt': prompt,
      if (placement != null) 'placement': placement!.toJson(),
      if (filenameHint != null) 'filename_hint': filenameHint,
      if (style != null) 'style': style,
    };
  }
}

class ResearchedImage {
  final String url;
  final String? source;
  final String? title;
  final int? width;
  final int? height;
  final String? license;
  final Map<String, dynamic>? raw;

  ResearchedImage({
    required this.url,
    this.source,
    this.title,
    this.width,
    this.height,
    this.license,
    this.raw,
  });

  factory ResearchedImage.fromJson(Map<String, dynamic> json) {
    return ResearchedImage(
      url: json['url'] as String? ?? '',
      source: json['source'] as String?,
      title: json['title'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      license: json['license'] as String?,
      raw: json['raw'] != null ? Map<String, dynamic>.from(json['raw']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      if (source != null) 'source': source,
      if (title != null) 'title': title,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (license != null) 'license': license,
      if (raw != null) 'raw': raw,
    };
  }
}

class ImageSelectionResult {
  final String imageRequestId;
  final List<ResearchedImage> selectedImages;

  ImageSelectionResult({
    required this.imageRequestId,
    required this.selectedImages,
  });

  factory ImageSelectionResult.fromJson(Map<String, dynamic> json) {
    return ImageSelectionResult(
      imageRequestId: json['image_request_id'] as String? ?? '',
      selectedImages: (json['selected_images'] as List<dynamic>? ?? [])
          .map((e) => ResearchedImage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image_request_id': imageRequestId,
      'selected_images': selectedImages.map((e) => e.toJson()).toList(),
    };
  }
}
