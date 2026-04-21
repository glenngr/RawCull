use rawcull_core::{Catalog, Rating};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

pub const RAWCULL_FFI_API_VERSION: u32 = 1;
const INVALID_RATING_MARKER: u8 = 255;

pub struct RawCullEngine {
    catalog: Catalog,
}

impl RawCullEngine {
    fn new() -> Self {
        Self {
            catalog: Catalog::default(),
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
            true
        }
        Err(_) => false,
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
        return false;
    };

    engine.catalog.set_rating_by_index(index, rating)
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
            rawcull_engine_free(engine);
        }
    }
}
