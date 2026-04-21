use rawcull_core::{Catalog, Rating, ThumbnailCache};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};

pub const RAWCULL_FFI_API_VERSION: u32 = 1;
const INVALID_RATING_MARKER: u8 = 255;

pub struct RawCullEngine {
    catalog: Catalog,
    cache_dir: PathBuf,
    last_error: Option<CString>,
}

impl RawCullEngine {
    fn new() -> Self {
        let default_cache_dir = std::env::temp_dir().join("rawcull_thumbnails");
        Self {
            catalog: Catalog::default(),
            cache_dir: default_cache_dir,
            last_error: None,
        }
    }
}

fn to_cstring_lossy(message: impl Into<String>) -> CString {
    let mut bytes = message.into().into_bytes();
    for b in &mut bytes {
        if *b == 0 {
            *b = b'?';
        }
    }
    CString::new(bytes).expect("CString creation must succeed after nul sanitization")
}

fn set_error(engine: &mut RawCullEngine, message: impl Into<String>) {
    engine.last_error = Some(to_cstring_lossy(message));
}

unsafe fn ptr_to_engine_mut<'a>(ptr: *mut RawCullEngine) -> Option<&'a mut RawCullEngine> {
    ptr.as_mut()
}

unsafe fn ptr_to_engine<'a>(ptr: *const RawCullEngine) -> Option<&'a RawCullEngine> {
    ptr.as_ref()
}

unsafe fn c_path_to_str<'a>(path: *const c_char) -> Option<&'a str> {
    if path.is_null() {
        return None;
    }

    let c_str = CStr::from_ptr(path);
    c_str.to_str().ok()
}

#[no_mangle]
pub extern "C" fn rawcull_ffi_api_version() -> u32 {
    RAWCULL_FFI_API_VERSION
}

#[no_mangle]
pub extern "C" fn rawcull_engine_new() -> *mut RawCullEngine {
    Box::into_raw(Box::new(RawCullEngine::new()))
}

/// Frees an engine pointer allocated by [`rawcull_engine_new`].
///
/// # Safety
/// `engine` must either be null or a valid pointer returned by `rawcull_engine_new`
/// that has not already been freed.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_free(engine: *mut RawCullEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// Scans a catalog directory and replaces the in-memory catalog.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
/// `path` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_scan_catalog(
    engine: *mut RawCullEngine,
    path: *const c_char,
) -> bool {
    let Some(engine) = ptr_to_engine_mut(engine) else {
        return false;
    };

    let Some(path_str) = c_path_to_str(path) else {
        return false;
    };

    match Catalog::load(Path::new(path_str)) {
        Ok(catalog) => {
            engine.catalog = catalog;
            engine.last_error = None;
            true
        }
        Err(err) => {
            set_error(engine, format!("scan_catalog failed: {err}"));
            false
        }
    }
}

/// Returns number of items in the currently loaded catalog.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_item_count(engine: *const RawCullEngine) -> usize {
    let Some(engine) = ptr_to_engine(engine) else {
        return 0;
    };

    engine.catalog.item_count()
}

/// Returns an allocated C string for item path at `index`.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
/// Caller must free returned pointer with [`rawcull_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_get_item_path(
    engine: *const RawCullEngine,
    index: usize,
) -> *mut c_char {
    let Some(engine) = ptr_to_engine(engine) else {
        return std::ptr::null_mut();
    };

    let Some(item) = engine.catalog.items().get(index) else {
        return std::ptr::null_mut();
    };

    to_cstring_lossy(item.path.to_string_lossy().to_string()).into_raw()
}

/// Returns rating value for item at `index`, or 255 on invalid input.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_get_item_rating(
    engine: *const RawCullEngine,
    index: usize,
) -> u8 {
    let Some(engine) = ptr_to_engine(engine) else {
        return INVALID_RATING_MARKER;
    };

    let Some(item) = engine.catalog.items().get(index) else {
        return INVALID_RATING_MARKER;
    };

    item.rating as u8
}

/// Sets rating for an item by index.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_set_item_rating(
    engine: *mut RawCullEngine,
    index: usize,
    rating_value: u8,
) -> bool {
    let Some(engine) = ptr_to_engine_mut(engine) else {
        return false;
    };

    let Ok(rating) = Rating::try_from(rating_value) else {
        set_error(engine, format!("invalid rating value: {rating_value}"));
        return false;
    };

    if engine.catalog.set_rating_by_index(index, rating) {
        engine.last_error = None;
        true
    } else {
        set_error(engine, format!("invalid index: {index}"));
        false
    }
}

/// Configures disk cache directory used for thumbnail artifacts.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
/// `cache_dir` must be a valid null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_set_cache_dir(
    engine: *mut RawCullEngine,
    cache_dir: *const c_char,
) -> bool {
    let Some(engine) = ptr_to_engine_mut(engine) else {
        return false;
    };

    let Some(cache_dir_str) = c_path_to_str(cache_dir) else {
        set_error(engine, "set_cache_dir: invalid UTF-8 or null pointer");
        return false;
    };

    engine.cache_dir = PathBuf::from(cache_dir_str);
    engine.last_error = None;
    true
}

/// Generates/refreshes a cached thumbnail artifact for an indexed item.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
/// Caller must free returned pointer with [`rawcull_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_cache_thumbnail(
    engine: *mut RawCullEngine,
    index: usize,
    max_bytes: usize,
) -> *mut c_char {
    let Some(engine) = ptr_to_engine_mut(engine) else {
        return std::ptr::null_mut();
    };

    let Some(item) = engine.catalog.items().get(index) else {
        set_error(engine, format!("cache_thumbnail: invalid index {index}"));
        return std::ptr::null_mut();
    };

    let cache = ThumbnailCache::new(engine.cache_dir.clone());
    match cache.cache_thumbnail_for_file(&item.path, max_bytes.max(1)) {
        Ok(path) => {
            engine.last_error = None;
            to_cstring_lossy(path.to_string_lossy().to_string()).into_raw()
        }
        Err(err) => {
            set_error(engine, format!("cache_thumbnail failed: {err}"));
            std::ptr::null_mut()
        }
    }
}

/// Returns last engine error as allocated C string, if any.
///
/// # Safety
/// `engine` must be a valid pointer returned by `rawcull_engine_new`.
/// Caller must free returned pointer with [`rawcull_string_free`].
#[no_mangle]
pub unsafe extern "C" fn rawcull_engine_get_last_error(
    engine: *const RawCullEngine,
) -> *mut c_char {
    let Some(engine) = ptr_to_engine(engine) else {
        return std::ptr::null_mut();
    };

    match &engine.last_error {
        Some(err) => to_cstring_lossy(err.to_string_lossy().to_string()).into_raw(),
        None => std::ptr::null_mut(),
    }
}

/// Frees a C string returned by this library.
///
/// # Safety
/// `ptr` must be null or a pointer previously returned by `rawcull_engine_get_item_path`
/// that has not yet been freed.
#[no_mangle]
pub unsafe extern "C" fn rawcull_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("rawcull_ffi_{label}_{nanos}"));
        fs::create_dir_all(&path).expect("create temp dir");
        path
    }

    #[test]
    fn ffi_api_version_is_stable() {
        assert_eq!(rawcull_ffi_api_version(), 1);
    }

    #[test]
    fn engine_scan_and_rating_flow_works() {
        let root = make_temp_dir("scan");
        let file = root.join("sample.ARW");
        fs::write(&file, b"x").expect("write file");

        let path_c = CString::new(root.to_string_lossy().to_string()).expect("cstring");

        let engine = rawcull_engine_new();
        assert!(!engine.is_null());

        unsafe {
            assert!(rawcull_engine_scan_catalog(engine, path_c.as_ptr()));
            assert_eq!(rawcull_engine_item_count(engine), 1);
            assert_eq!(rawcull_engine_get_item_rating(engine, 0), 0);
            assert!(rawcull_engine_set_item_rating(engine, 0, 5));
            assert_eq!(rawcull_engine_get_item_rating(engine, 0), 5);

            let c_path = rawcull_engine_get_item_path(engine, 0);
            assert!(!c_path.is_null());
            let str_path = CStr::from_ptr(c_path).to_string_lossy().to_string();
            assert!(str_path.ends_with("sample.ARW"));
            rawcull_string_free(c_path);

            rawcull_engine_free(engine);
        }

        fs::remove_dir_all(root).expect("cleanup");
    }

    #[test]
    fn engine_rejects_invalid_rating() {
        let engine = rawcull_engine_new();
        unsafe {
            assert!(!rawcull_engine_set_item_rating(engine, 0, 7));
            let err = rawcull_engine_get_last_error(engine);
            assert!(!err.is_null());
            rawcull_string_free(err);
            rawcull_engine_free(engine);
        }
    }

    #[test]
    fn engine_caches_thumbnail_to_disk() {
        let root = make_temp_dir("thumb");
        let catalog_dir = root.join("catalog");
        let cache_dir = root.join("cache");
        fs::create_dir_all(&catalog_dir).expect("create catalog");
        fs::create_dir_all(&cache_dir).expect("create cache");

        let file = catalog_dir.join("sample.ARW");
        fs::write(&file, b"0123456789abcdef").expect("write source");

        let catalog_c = CString::new(catalog_dir.to_string_lossy().to_string()).expect("cstring");
        let cache_c = CString::new(cache_dir.to_string_lossy().to_string()).expect("cstring");

        let engine = rawcull_engine_new();
        unsafe {
            assert!(rawcull_engine_set_cache_dir(engine, cache_c.as_ptr()));
            assert!(rawcull_engine_scan_catalog(engine, catalog_c.as_ptr()));
            let cached = rawcull_engine_cache_thumbnail(engine, 0, 6);
            assert!(!cached.is_null());

            let cache_path = CStr::from_ptr(cached).to_string_lossy().to_string();
            rawcull_string_free(cached);

            let bytes = fs::read(cache_path).expect("read cached thumb");
            assert_eq!(bytes, b"012345");

            rawcull_engine_free(engine);
        }

        fs::remove_dir_all(root).expect("cleanup");
    }
}
