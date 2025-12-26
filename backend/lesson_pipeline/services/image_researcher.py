"""
Image research service - wrapper around existing image_researcher app.
"""
import logging
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests

from lesson_pipeline.types import ImageCandidate
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Add wb_research app to path for Imageresearcher
WB_RESEARCH_DIR = Path(__file__).parent.parent.parent / 'wb_research'
if str(WB_RESEARCH_DIR) not in sys.path:
    sys.path.insert(0, str(WB_RESEARCH_DIR))

# Lazy import - will be loaded on first use
ir = None
IMAGE_RESEARCHER_AVAILABLE = None


def _get_image_researcher():
    """Lazy load Imageresearcher module."""
    global ir, IMAGE_RESEARCHER_AVAILABLE
    if IMAGE_RESEARCHER_AVAILABLE is None:
        try:
            import Imageresearcher as _ir
            ir = _ir
            IMAGE_RESEARCHER_AVAILABLE = True
            logger.info("Imageresearcher module loaded from wb_research")
        except ImportError as e:
            logger.warning(f"Could not import Imageresearcher: {e}")
            IMAGE_RESEARCHER_AVAILABLE = False
    return ir if IMAGE_RESEARCHER_AVAILABLE else None


class ImageResearchService:
    """Service for researching educational images"""
    
    def __init__(self):
        self.max_images = config.max_images_per_prompt
        self.api_url = config.image_research_api_url
        self.api_token = config.image_research_api_token
        self.timeout = config.image_research_timeout

    def _research_via_api(
        self,
        query: str,
        subject: str,
        limit: int,
    ) -> List[ImageCandidate]:
        """Call the external image research API and normalize results."""
        if not self.api_url:
            logger.debug("Image research API URL is not configured")
            return []

        payload = {
            "query": query,
            "subject": subject,
            "limit": limit,
        }
        headers = {
            "Content-Type": "application/json",
        }
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"

        try:
            response = requests.post(
                self.api_url,
                json=payload,
                headers=headers,
                timeout=self.timeout,
            )
            response.raise_for_status()
            data = response.json()
        except Exception as exc:
            logger.error("Image research API request failed: %s", exc)
            return []

        if not data.get("ok"):
            logger.warning("Image research API returned non-ok payload: %s", data)
            return []

        candidates: List[ImageCandidate] = []
        for source_entry in data.get("results", []):
            source_name = source_entry.get("source") or "unknown"
            images = source_entry.get("images") or []
            metadata_list = (
                source_entry.get("metadata")
                or source_entry.get("image_metadata")
                or []
            )

            for idx, image_ref in enumerate(images):
                meta = self._coerce_metadata(metadata_list, idx)
                normalized_ref = self._normalize_image_reference(image_ref)
                candidate = ImageCandidate(
                    source_url=normalized_ref,
                    source=source_name,
                    title=self._derive_title(meta, normalized_ref, query),
                    description=meta.get("description")
                    or f"{subject}: {query}",
                    width=self._safe_int(
                        meta.get("width") or meta.get("image_width")
                    ),
                    height=self._safe_int(
                        meta.get("height") or meta.get("image_height")
                    ),
                    license=meta.get("license"),
                    tags=self._build_tags(query, subject, meta),
                    metadata=self._build_candidate_metadata(
                        meta,
                        source_name,
                        subject,
                        query,
                        normalized_ref,
                    ),
                )
                candidates.append(candidate)
                if len(candidates) >= limit:
                    return candidates

        return candidates

    def _normalize_image_reference(self, value: Any) -> str:
        if value is None:
            return ""
        try:
            path = Path(value)
            if path.exists():
                return str(path.resolve())
        except (OSError, TypeError, ValueError):
            pass
        return str(value)

    def _coerce_metadata(
        self,
        metadata_list: Any,
        index: int,
    ) -> Dict[str, Any]:
        if isinstance(metadata_list, list) and 0 <= index < len(metadata_list):
            entry = metadata_list[index]
            if isinstance(entry, dict):
                return dict(entry)
        return {}

    def _derive_title(
        self,
        meta: Dict[str, Any],
        image_ref: str,
        query: str,
    ) -> str:
        if meta.get("title"):
            return meta["title"]
        if image_ref:
            return Path(image_ref).stem.replace("_", " ") or query
        return query

    def _build_tags(
        self,
        query: str,
        subject: str,
        meta: Dict[str, Any],
    ) -> List[str]:
        tags = [query, subject]
        extra = meta.get("tags")
        if isinstance(extra, list):
            tags.extend([str(tag) for tag in extra if tag])
        return list(dict.fromkeys(t for t in tags if t))

    def _build_candidate_metadata(
        self,
        meta: Dict[str, Any],
        source_name: str,
        subject: str,
        query: str,
        image_ref: str,
    ) -> Dict[str, Any]:
        metadata = {
            "source_name": source_name,
            "subject": subject,
            "query": query,
            "image_ref": image_ref,
        }
        if isinstance(meta, dict):
            metadata.update(meta)
        return metadata

    @staticmethod
    def _safe_int(value: Any) -> Optional[int]:
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None
    
    def _duckduckgo_search(self, query: str, subject: str, limit: int) -> List[ImageCandidate]:
        """Search for images using DuckDuckGo as fallback."""
        candidates = []
        try:
            from duckduckgo_search import DDGS
            
            search_query = f"{subject} {query} diagram illustration"
            logger.info(f"  DDG search: '{search_query}'")
            
            with DDGS() as ddgs:
                results = ddgs.images(search_query, max_results=min(30, limit), safesearch="moderate")
                
                for result in results:
                    if len(candidates) >= limit:
                        break
                    
                    url = result.get("image")
                    if url:
                        candidate = ImageCandidate(
                            source_url=url,
                            source="duckduckgo",
                            title=result.get("title", query),
                            description=result.get("title", f"{subject}: {query}"),
                            width=result.get("width"),
                            height=result.get("height"),
                            tags=[query, subject]
                        )
                        candidates.append(candidate)
                
                logger.info(f"  DDG: Found {len(candidates)} images")
        
        except Exception as e:
            logger.warning(f"DuckDuckGo search failed: {e}")
        
        return candidates

    def _extract_urls_from_api_data(self, source_name: str, data: dict) -> List[str]:
        """
        Extract image URLs directly from API response data.
        This bypasses the download step that the original parsers do.
        """
        urls = []
        
        try:
            logger.debug(f"  Extracting URLs from {source_name}, data type: {type(data)}")
            
            if source_name == "wikimedia":
                if isinstance(data, dict):
                    logger.debug(f"    Data keys: {list(data.keys())}")
                    pages = data.get("query", {}).get("pages", {})
                    logger.debug(f"    Pages count: {len(pages)}")
                    for page in pages.values():
                        info = page.get("imageinfo", [])
                        logger.debug(f"    Imageinfo entries: {len(info)}")
                        for img_info in info:
                            url = img_info.get("url")
                            if url:
                                urls.append(url)
                                logger.debug(f"    Found URL: {url[:80]}...")
            
            elif source_name == "openverse":
                if isinstance(data, dict):
                    results = data.get("results", [])
                    logger.debug(f"    Results count: {len(results)}")
                    for item in results:
                        url = item.get("url")
                        if url:
                            urls.append(url)
                            logger.debug(f"    Found URL: {url[:80]}...")
            
            elif source_name == "plos":
                # PLOS API returns DOIs, we need to extract figure URLs from metadata
                if isinstance(data, dict):
                    docs = data.get("response", {}).get("docs", [])
                    logger.info(f"  PLOS: Found {len(docs)} documents, extracting figure metadata...")
                    
                    for doc in docs[:10]:  # Limit to first 10
                        # Try to extract figure captions which sometimes contain URLs
                        figure_caption = doc.get("figure_table_caption", [])
                        if figure_caption:
                            logger.debug(f"    Doc has {len(figure_caption)} figure captions")
                        
                        # PLOS images are at predictable URLs based on DOI
                        doi = doc.get("doi") or doc.get("id")
                        if doi:
                            # PLOS images follow pattern: https://journals.plos.org/plosone/article/figure/image?size=large&id=10.1371/journal.pone.XXXXXX.gXXX
                            # But we don't know the figure IDs without fetching the article
                            # So skip for now
                            pass
            
            elif source_name == "usgs":
                if isinstance(data, dict):
                    items = data.get("items", [])
                    logger.debug(f"    Items count: {len(items)}")
                    for item in items:
                        files = item.get("files", []) + item.get("attachments", [])
                        logger.debug(f"    Files count: {len(files)}")
                        for file_entry in files:
                            url = file_entry.get("url") or file_entry.get("downloadUri")
                            if url:
                                # Check if it's an image
                                ctype = (file_entry.get("contentType") or "").lower()
                                if "image/" in ctype:
                                    urls.append(url)
                                    logger.debug(f"    Found URL: {url[:80]}...")
        
        except Exception as e:
            logger.warning(f"Failed to extract URLs from {source_name}: {e}")
            import traceback
            logger.debug(traceback.format_exc())
        
        logger.info(f"  {source_name}: Extracted {len(urls)} URLs")
        return urls
    
    def research_images(
        self,
        query: str,
        subject: str = "General",
        max_images: int = None
    ) -> List[ImageCandidate]:
        """
        Research images for a given query and subject.
        
        Args:
            query: Search query
            subject: Subject area (Maths, Physics, Biology, Chemistry, Geography)
            max_images: Maximum number of images to return
        
        Returns:
            List of ImageCandidate objects
        """
        limit = max_images or self.max_images
        
        logger.info(f"Researching images for query='{query}', subject='{subject}', limit={limit}")

        api_candidates = self._research_via_api(query, subject, limit)
        if api_candidates:
            logger.info("Image research API returned %s candidates", len(api_candidates))
            return api_candidates[:limit]

        ir_module = _get_image_researcher()
        if ir_module is None:
            logger.warning("Image researcher module not available, using DuckDuckGo fallback")
            return self._duckduckgo_search(query, subject, limit)
        
        try:
            # Read sources
            sources = ir_module.read_sources()
            
            candidates = []
            
            for src in sources:
                try:
                    if src.type == "API":
                        # API-based source with OAuth2 support for Openverse
                        settings = {
                            "query_field": query,
                            "limit_field": limit,
                            "pagination_field": 1,
                            "format_field": "json",
                        }
                        
                        status, data, _ = ir_module.send_request(src, settings)
                        logger.info(f"  API {src.name}: status={status}, has_data={data is not None}")
                        
                        if status == 200 and data is not None:
                            # Extract URLs and metadata from API response
                            if src.name == "wikimedia":
                                pages = data.get("query", {}).get("pages", {})
                                for page in pages.values():
                                    info = page.get("imageinfo", [])
                                    for img_info in info:
                                        url = img_info.get("url")
                                        if url:
                                            candidate = ImageCandidate(
                                                source_url=url,
                                                source=src.name,
                                                title=page.get("title", "").replace("File:", ""),
                                                description=img_info.get("extmetadata", {}).get("ImageDescription", {}).get("value", query),
                                                tags=[query, subject]
                                            )
                                            candidates.append(candidate)
                                            if len(candidates) >= limit:
                                                break
                            
                            elif src.name == "openverse":
                                results = data.get("results", [])
                                for item in results:
                                    url = item.get("url")
                                    if url:
                                        candidate = ImageCandidate(
                                            source_url=url,
                                            source=src.name,
                                            title=item.get("title", query),
                                            description=item.get("description") or item.get("title") or query,
                                            tags=[query, subject]
                                        )
                                        candidates.append(candidate)
                                        if len(candidates) >= limit:
                                            break
                            
                            elif src.name == "usgs":
                                items = data.get("items", [])
                                for item in items:
                                    files = item.get("files", []) + item.get("attachments", [])
                                    for file_entry in files:
                                        url = file_entry.get("url") or file_entry.get("downloadUri")
                                        ctype = (file_entry.get("contentType") or "").lower()
                                        if url and "image/" in ctype:
                                            candidate = ImageCandidate(
                                                source_url=url,
                                                source=src.name,
                                                title=item.get("title", query),
                                                description=item.get("summary") or item.get("title") or query,
                                                tags=[query, subject]
                                            )
                                            candidates.append(candidate)
                                            if len(candidates) >= limit:
                                                break
                            
                            else:
                                # Fallback: just extract URLs
                                img_urls = self._extract_urls_from_api_data(src.name, data)
                                for img_url in img_urls[:limit]:
                                    candidate = ImageCandidate(
                                        source_url=img_url,
                                        source=src.name,
                                        title=f"{query} from {src.name}",
                                        description=f"Educational image for {subject}: {query}",
                                        tags=[query, subject]
                                    )
                                    candidates.append(candidate)
                                    if len(candidates) >= limit:
                                        break
                    else:
                        # Non-API source (scraping)
                        ir_module.handle_result_no_api(src, query, subject, hard_image_cap=limit)
                        
                        # Collect results from this source
                        images = getattr(src, 'img_paths', [])
                        logger.info(f"  Source {src.name}: found {len(images)} images")
                        
                        for img_path in images:
                            # Convert to ImageCandidate with metadata
                            candidate = ImageCandidate(
                                source_url=img_path,
                                source=src.name,
                                title=f"{query} from {src.name}",
                                description=f"Educational image for {subject}: {query}",
                                tags=[query, subject]
                            )
                            candidates.append(candidate)
                            
                            if len(candidates) >= limit:
                                break
                    
                except Exception as e:
                    logger.warning(f"Failed to research from {src.name}: {e}")
                    import traceback
                    logger.debug(traceback.format_exc())
                    continue
                
                if len(candidates) >= limit:
                    break
            
            logger.info(f"Found {len(candidates)} images from API sources")
            
            # If we didn't get enough images, try DuckDuckGo as fallback
            if len(candidates) < 5:
                logger.info(f"  Not enough images ({len(candidates)}), trying DuckDuckGo fallback...")
                try:
                    from duckduckgo_search import DDGS
                    
                    search_query = f"{subject} {query} diagram illustration"
                    logger.info(f"  DDG search: '{search_query}'")
                    
                    with DDGS() as ddgs:
                        results = ddgs.images(search_query, max_results=min(20, limit), safesearch="moderate")
                        
                        for result in results:
                            if len(candidates) >= limit:
                                break
                            
                            url = result.get("image")
                            if url:
                                candidate = ImageCandidate(
                                    source_url=url,
                                    source="duckduckgo",
                                    title=result.get("title", ""),
                                    description=result.get("title", ""),
                                    tags=[query, subject]
                                )
                                candidates.append(candidate)
                        
                        logger.info(f"  DDG: Found {len([c for c in candidates if c.source == 'duckduckgo'])} additional images")
                
                except Exception as e:
                    logger.warning(f"DuckDuckGo fallback failed: {e}")
            
            logger.info(f"✅ Total found: {len(candidates)} images")
            return candidates[:limit]
            
        except Exception as e:
            logger.error(f"Failed to research images: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return []


# Global singleton
_image_research_service: ImageResearchService = None


def get_image_research_service() -> ImageResearchService:
    """Get or create the global image research service"""
    global _image_research_service
    if _image_research_service is None:
        _image_research_service = ImageResearchService()
    return _image_research_service


# Convenience function
def research_images(query: str, subject: str = "General", max_images: int = None) -> List[ImageCandidate]:
    """Research images for a query"""
    return get_image_research_service().research_images(query, subject, max_images)

