use std::time::Duration;

use sctk::{reexports::client::Connection, registry::{RegistryState, SimpleGlobal}};
use smithay_client_toolkit as sctk;
use state::CadenzaLockState;

mod state;

fn main() {
    let connection = Connection::connect_to_env().expect("couldn't connect to wayland compositor");
    let mut event_queue = connection.new_event_queue::<CadenzaLockState>();
    let qh = event_queue.handle();

    let mut state = CadenzaLockState {
        registry_state: RegistryState::new(&connection, &qh),
        lock_manager: SimpleGlobal::new(),
    };

    event_queue.roundtrip(&mut state).unwrap();

    let lock_manager = state.lock_manager.get().expect("no lock manager found");
    let lock = lock_manager.lock(&qh, ()).unwrap();

    std::thread::sleep(Duration::from_secs(5));

    lock.unlock_and_destroy();
}
