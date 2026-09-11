use mlua::Lua;

#[test]
fn test_nil_index() {
    let lua = Lua::new();
    let res = lua.load("local t = {1, 2, 3}; local x = t[nil]; return x").exec();
    println!("{:?}", res);
    assert!(res.is_err());
}
