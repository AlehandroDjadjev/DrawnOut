"""DRF serializers that define the shared image pipeline contracts."""
from rest_framework import serializers


class ImagePlacementSerializer(serializers.Serializer):
    """Normalized placement ratios for an image region."""
    x = serializers.FloatField()
    y = serializers.FloatField()
    width = serializers.FloatField()
    height = serializers.FloatField()
    scale = serializers.FloatField(required=False, allow_null=True)


class ScriptImageRequestSerializer(serializers.Serializer):
    """Structured request describing an image the script needs."""
    id = serializers.CharField()
    prompt = serializers.CharField()
    placement = ImagePlacementSerializer(required=False, allow_null=True)
    filename_hint = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True,
    )
    style = serializers.CharField(required=False, allow_blank=True, allow_null=True)


class ScriptOutputSerializer(serializers.Serializer):
    """Script output enriched with optional image requests."""
    id = serializers.CharField(required=False, allow_blank=True)
    prompt_id = serializers.CharField(required=False, allow_blank=True)
    content = serializers.CharField()
    image_requests = ScriptImageRequestSerializer(
        many=True,
        required=False,
        default=list,
    )


class ResearchedImageSerializer(serializers.Serializer):
    """Normalized image returned from research providers."""
    url = serializers.URLField()
    source = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    title = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    width = serializers.IntegerField(required=False, allow_null=True)
    height = serializers.IntegerField(required=False, allow_null=True)
    license = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    raw = serializers.JSONField(required=False, default=dict)












