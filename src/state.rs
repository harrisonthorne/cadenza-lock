use smithay_client_toolkit::{registry::{RegistryState, RegistryHandler, ProvidesRegistryState, SimpleGlobal}, delegate_registry, registry_handlers, delegate_simple, reexports::client::{Dispatch, Connection, QueueHandle, Proxy}};
use wayland_protocols::ext::session_lock::v1::client::{ext_session_lock_v1::{ExtSessionLockV1, Event}, ext_session_lock_manager_v1::ExtSessionLockManagerV1};

pub struct CadenzaLockState {
    pub registry_state: RegistryState,
    pub lock_manager: SimpleGlobal<ExtSessionLockManagerV1, 1>,
}

impl CadenzaLockState {
}

impl ProvidesRegistryState for CadenzaLockState {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }

    registry_handlers!(SimpleGlobal<ExtSessionLockManagerV1, 1>);
}

impl AsMut<SimpleGlobal<ExtSessionLockManagerV1, 1>> for CadenzaLockState {
    fn as_mut(&mut self) -> &mut SimpleGlobal<ExtSessionLockManagerV1, 1> {
        &mut self.lock_manager
    }
}

impl Dispatch<ExtSessionLockV1, ()> for CadenzaLockState {
    fn event(
        state: &mut Self,
        proxy: &ExtSessionLockV1,
        event: <ExtSessionLockV1 as Proxy>::Event,
        data: &(),
        conn: &Connection,
        qhandle: &QueueHandle<Self>,
    ) {
        match event {
            Event::Locked => println!("locked!"),
            Event::Finished => {
                println!("finished! unlocking and cleaning up");
                proxy.unlock_and_destroy();
            },
            _ => todo!(),
        }
    }
}

delegate_registry!(CadenzaLockState);
delegate_simple!(CadenzaLockState, ExtSessionLockManagerV1, 1);
