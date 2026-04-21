use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Rating {
    Unrated = 0,
    One = 1,
    Two = 2,
    Three = 3,
    Four = 4,
    Five = 5,
}

impl TryFrom<u8> for Rating {
    type Error = RatingParseError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Unrated),
            1 => Ok(Self::One),
            2 => Ok(Self::Two),
            3 => Ok(Self::Three),
            4 => Ok(Self::Four),
            5 => Ok(Self::Five),
            _ => Err(RatingParseError(value)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RatingParseError(pub u8);

impl fmt::Display for RatingParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid rating value: {}", self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CatalogItem {
    pub id: String,
    pub path: PathBuf,
    pub rating: Rating,
}

impl CatalogItem {
    pub fn new(path: PathBuf) -> Self {
        let id = path.to_string_lossy().to_string();
        Self {
            id,
            path,
            rating: Rating::Unrated,
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct Catalog {
    items: Vec<CatalogItem>,
}

impl Catalog {
    pub fn load(path: &Path) -> std::io::Result<Self> {
        let mut items = Vec::new();
        collect_supported_files(path, &mut items)?;
        items.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(Self { items })
    }

    pub fn items(&self) -> &[CatalogItem] {
        &self.items
    }

    pub fn item_count(&self) -> usize {
        self.items.len()
    }

    pub fn set_rating_by_index(&mut self, index: usize, rating: Rating) -> bool {
        let Some(item) = self.items.get_mut(index) else {
            return false;
        };
        item.rating = rating;
        true
    }

    pub fn set_rating_by_id(&mut self, id: &str, rating: Rating) -> bool {
        let Some(item) = self.items.iter_mut().find(|i| i.id == id) else {
            return false;
        };
        item.rating = rating;
        true
    }
}

pub fn is_supported_extension(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };

    matches!(
        ext.to_ascii_lowercase().as_str(),
        "arw" | "nef" | "jpg" | "jpeg"
    )
}

pub fn scan_catalog(path: &Path) -> std::io::Result<Vec<CatalogItem>> {
    Ok(Catalog::load(path)?.items)
}

fn collect_supported_files(path: &Path, out: &mut Vec<CatalogItem>) -> std::io::Result<()> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let entry_path = entry.path();

        if entry_path.is_dir() {
            collect_supported_files(&entry_path, out)?;
        } else if entry_path.is_file() && is_supported_extension(&entry_path) {
            out.push(CatalogItem::new(entry_path));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("rawcull_core_{label}_{nanos}"));
        fs::create_dir_all(&path).expect("create temp dir");
        path
    }

    #[test]
    fn recognizes_supported_extensions_case_insensitive() {
        assert!(is_supported_extension(Path::new("a.ARW")));
        assert!(is_supported_extension(Path::new("a.nef")));
        assert!(is_supported_extension(Path::new("a.JpEg")));
        assert!(!is_supported_extension(Path::new("a.png")));
    }

    #[test]
    fn catalog_item_defaults_to_unrated() {
        let item = CatalogItem::new(PathBuf::from("/tmp/test.arw"));
        assert_eq!(item.rating, Rating::Unrated);
        assert_eq!(item.id, "/tmp/test.arw");
    }

    #[test]
    fn recursive_scan_collects_nested_supported_files() {
        let root = make_temp_dir("scan");
        let nested = root.join("a").join("b");
        fs::create_dir_all(&nested).expect("create nested");

        let file1 = root.join("one.ARW");
        let file2 = nested.join("two.nef");
        let ignored = nested.join("ignore.txt");

        fs::write(&file1, b"x").expect("write file1");
        fs::write(&file2, b"x").expect("write file2");
        fs::write(&ignored, b"x").expect("write ignored");

        let catalog = Catalog::load(&root).expect("scan");
        assert_eq!(catalog.item_count(), 2);
        let scanned: Vec<PathBuf> = catalog.items().iter().map(|i| i.path.clone()).collect();
        assert!(scanned.contains(&file1));
        assert!(scanned.contains(&file2));

        fs::remove_dir_all(root).expect("cleanup");
    }

    #[test]
    fn set_rating_by_id_updates_item() {
        let root = make_temp_dir("rating");
        let file1 = root.join("one.ARW");
        fs::write(&file1, b"x").expect("write file1");

        let mut catalog = Catalog::load(&root).expect("scan");
        let id = catalog.items()[0].id.clone();

        assert!(catalog.set_rating_by_id(&id, Rating::Four));
        assert_eq!(catalog.items()[0].rating, Rating::Four);
        assert!(!catalog.set_rating_by_id("missing", Rating::One));

        fs::remove_dir_all(root).expect("cleanup");
    }
}
