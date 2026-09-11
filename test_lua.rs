fn main() {
    let lua = mlua::Lua::new();
    let result = lua.load("local t = {1, 2, 3}; return t[nil]").exec();
    println!("{:?}", result);
}
