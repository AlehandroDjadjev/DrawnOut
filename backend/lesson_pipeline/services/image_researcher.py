"""
Image research service - wrapper around existing image_researcher app.
"""
import logging
from typing import List

from lesson_pipeline.types import ImageCandidate
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Lazy import - will be loaded on first use
ir = None
IMAGE_RESEARCHER_AVAILABLE = None


def _get_image_researcher():
    """
    Load Imageresearcher module. Crashes with clear error if it fails.
    NO FALLBACKS - if this fails, fix the dependencies.
    Must import via wb_research package so Imageresearcher's relative imports
    (from .ddg_research, .smart_hits) resolve correctly.
    """
    global ir, IMAGE_RESEARCHER_AVAILABLE
    if IMAGE_RESEARCHER_AVAILABLE is None:
        try:
            from wb_research import Imageresearcher as _ir
            ir = _ir
            IMAGE_RESEARCHER_AVAILABLE = True
            logger.info("Imageresearcher module loaded from wb_research")
        except ImportError as e:
            IMAGE_RESEARCHER_AVAILABLE = False
            error_msg = f"""
================================================================================
FATAL: Cannot import Imageresearcher module

Error: {e}

This module is REQUIRED for image research. To fix:

    cd DrawnOut/backend
    pip install sentence-transformers
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

================================================================================
"""
            logger.error(error_msg)
            raise ImportError(f"Imageresearcher import failed: {e}") from e
    
    return ir


class ImageResearchService:
    """Service for researching educational images"""
    
    def __init__(self):
        self.max_images = config.max_images_per_prompt
    
    def _duckduckgo_search(self, query: str, subject: str, limit: int) -> List[ImageCandidate]:
        """Search for images using DuckDuckGo as fallback."""
        candidates = []
        try:
            from duckduckgo_search import DDGS
            
            search_query = f"{subject} {query} diagram illustration"
            logger.info(f"DDG fallback search: '{search_query}'")
            
            with DDGS() as ddgs:
                results = list(ddgs.images(search_query, max_results=min(30, limit), safesearch="moderate"))
                
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
                
                logger.info(f"DDG fallback: Found {len(candidates)} images")
        
        except Exception as e:
            logger.warning(f"DuckDuckGo search failed: {e}")
            import traceback
            logger.debug(traceback.format_exc())
        
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
        
        # Load Imageresearcher module - will crash if not available
        ir_module = _get_image_researcher()
        
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
                                # Separate raster images from SVGs - prefer raster
                                raster_candidates = []
                                svg_candidates = []
                                
                                for page in pages.values():
                                    info = page.get("imageinfo", [])
                                    for img_info in info:
                                        url = img_info.get("url")
                                        
                                        if not url:
                                            continue
                                        
                                        candidate = ImageCandidate(
                                            source_url=url,
                                            source=src.name,
                                            title=page.get("title", "").replace("File:", ""),
                                            description=img_info.get("extmetadata", {}).get("ImageDescription", {}).get("value", query),
                                            tags=[query, subject]
                                        )
                                        
                                        # Prioritize raster images (PNG, JPG) over SVG
                                        url_lower = url.lower()
                                        if '.svg' in url_lower:
                                            svg_candidates.append(candidate)
                                        else:
                                            raster_candidates.append(candidate)
                                
                                # Add raster first, then SVGs if we need more
                                for c in raster_candidates:
                                    candidates.append(c)
                                    if len(candidates) >= limit:
                                        break
                                
                                if len(candidates) < limit:
                                    for c in svg_candidates:
                                        candidates.append(c)
                                        if len(candidates) >= limit:
                                            break
                            
                            elif src.name == "openverse":
                                results = data.get("results", [])
                                for item in results:
                                    url = item.get("url")
                                    if url:
                                        # SVG/GIF are now converted to PNG during embedding
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
                                            # SVG/GIF are now converted to PNG during embedding
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
                                    # SVG/GIF are now converted to PNG during embedding
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
                            # SVG/GIF are now converted to PNG during embedding
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
                        results = list(ddgs.images(search_query, max_results=min(20, limit), safesearch="moderate"))
                        
                        for result in results:
                            if len(candidates) >= limit:
                                break
                            
                            url = result.get("image")
                            if url:
                                # SVG/GIF are now converted to PNG during embedding
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
            
            logger.info(f"Total found: {len(candidates)} images")
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
