use mlua::{AnyUserData, UserDataRegistry};

use crate::file::File;

#[allow(clippy::type_complexity)]
pub struct FileInventory {
	pub register: fn(&mut UserDataRegistry<File>),
	pub borrow: fn(&AnyUserData, &mut dyn FnMut(&File) -> mlua::Result<()>) -> mlua::Result<()>,
}

inventory::collect!(FileInventory);
