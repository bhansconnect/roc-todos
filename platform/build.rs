fn main() {
    println!("cargo:rustc-link-lib=dylib=app");
    println!("cargo:rustc-link-search=.");
    println!("cargo:rerun-if-changed=../migrations");
}
