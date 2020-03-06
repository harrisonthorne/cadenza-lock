use smithay_client_toolkit::{
    environment::MultiGlobalHandler,
    reexports::{
        client::protocol::{wl_output, wl_registry},
        client::{Attached, DispatchData},
    },
};

use std::boxed::Box;

pub struct LockOutputHandler {
    outputs: Vec<(u32, Attached<wl_output::WlOutput>)>,
    created_listener: Option<Box<dyn Fn(u32, wl_output::WlOutput)>>,
    removed_listener: Option<Box<dyn Fn(u32)>>,
}

impl LockOutputHandler {
    pub fn new() -> Self {
        Self {
            outputs: Vec::new(),
            created_listener: None,
            removed_listener: None,
        }
    }
}

impl MultiGlobalHandler<wl_output::WlOutput> for LockOutputHandler {
    fn created(
        &mut self,
        registry: Attached<wl_registry::WlRegistry>,
        id: u32,
        version: u32,
        _data: DispatchData,
    ) {
        let output = registry.bind::<wl_output::WlOutput>(version, id);
        output.quick_assign(|_, _, _| { /* ignore all events */ });
        self.outputs.push((id, (*output).clone()));
        if let Some(listener) = &self.created_listener {
            listener(id, output.detach());
        }
    }

    fn removed(&mut self, id: u32, _data: DispatchData) {
        if let Some(listener) = &self.removed_listener {
            listener(id);
        }
        self.outputs.retain(|(i, _)| *i != id);
    }

    fn get_all(&self) -> Vec<Attached<wl_output::WlOutput>> {
        self.outputs.iter().map(|(_, o)| o.clone()).collect()
    }
}
