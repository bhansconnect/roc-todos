#![allow(non_snake_case)]

use std::convert::Infallible;
use std::ffi::{c_void, CStr};
use std::mem::MaybeUninit;
use std::os::raw::c_char;

use hyper::header::HeaderValue;
use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Method, Request, Response, Server, StatusCode};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions, SqliteRow};
use sqlx::{Column, Row, TypeInfo};
use tokio::runtime::Runtime;

use roc_std::{RocList, RocResult, RocStr};

// The glue code can't generate everything, but at least it can generate SqlData type.
mod glue;
use glue::{discriminant_SqlData, SqlData, SqlError};

extern "C" {
    #[link_name = "roc__mainForHost_1_exposed_generic"]
    fn roc_main(closure_data: *mut u8, req: *const Request<Body>);

    #[link_name = "roc__mainForHost_size"]
    fn roc_main_size() -> usize;

    #[link_name = "roc__mainForHost_1__Continuation_caller"]
    // The last field should be a pionter to a pionter, but we take it as a usize instead.
    fn call_Continuation(flags: *const u8, closure_data: *const u8, cont_ptr: *mut usize);

    #[link_name = "roc__mainForHost_1__Continuation_result_size"]
    fn call_Continuation_result_size() -> usize;

    #[link_name = "roc__mainForHost_1__DBFetchOneCont_caller"]
    fn call_DBFetchOneCont(
        flags: *const RocResult<RocList<SqlData>, SqlError>,
        closure_data: *const u8,
        output: *mut usize,
    );

    #[link_name = "roc__mainForHost_1__DBFetchOneCont_result_size"]
    fn call_DBFetchOneCont_result_size() -> usize;

    #[link_name = "roc__mainForHost_1__LoadBodyCont_caller"]
    fn call_LoadBodyCont(
        flags: *const RocResult<RocStr, ()>,
        closure_data: *const u8,
        output: *mut usize,
    );

    #[link_name = "roc__mainForHost_1__LoadBodyCont_result_size"]
    fn call_LoadBodyCont_result_size() -> usize;
}

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct TraitObject {
    pub data: *mut (),
    pub vtable: *mut (),
}

static mut RT: MaybeUninit<Runtime> = MaybeUninit::uninit();

#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let out = libc::malloc(size);
    log::trace!("Allocating {} bytes at 0x{:?}", size, out);
    out
}

#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut c_void,
    new_size: usize,
    old_size: usize,
    _alignment: u32,
) -> *mut c_void {
    let out = libc::realloc(c_ptr, new_size);
    log::trace!(
        "reallocating {} bytes at 0x{:?} to {} at 0x{:?}",
        old_size,
        c_ptr,
        new_size,
        out
    );
    out
}

#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut c_void, _alignment: u32) {
    log::trace!("freeing at 0x{:?}", c_ptr);
    libc::free(c_ptr);
}

#[no_mangle]
pub unsafe extern "C" fn roc_panic(c_ptr: *mut c_void, tag_id: u32) {
    match tag_id {
        0 => {
            let slice = CStr::from_ptr(c_ptr as *const c_char);
            let string = slice.to_str().unwrap();
            println!("Roc hit a panic: {}", string);
            std::process::exit(1);
        }
        _ => todo!(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn roc_memcpy(dst: *mut c_void, src: *mut c_void, n: usize) -> *mut c_void {
    libc::memcpy(dst, src, n)
}

#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    libc::memset(dst, c, n)
}

#[repr(C)]
struct RocHeader {
    k: RocStr,
    v: RocStr,
}

#[repr(C)]
struct RocResponse {
    body: RocStr,
    headers: RocList<RocHeader>,
    status: u16,
}

fn translate_row(row: SqliteRow) -> RocList<SqlData> {
    RocList::from_iter(row.columns().iter().map(|col| {
        // Some reason they only expose the name and not the enum.
        match col.type_info().name() {
            "TEXT" => {
                let text: Option<&str> = row.get_unchecked(col.ordinal());
                match text {
                    Some(x) => SqlData::Text(unsafe { RocStr::from_slice_unchecked(x.as_bytes()) }),
                    None => SqlData::Null,
                }
            }
            "BOOLEAN" => match row.get_unchecked(col.ordinal()) {
                Some(x) => SqlData::Boolean(x),
                None => SqlData::Null,
            },
            "INTEGER" => match row.get_unchecked(col.ordinal()) {
                Some(x) => SqlData::Int(x),
                None => SqlData::Null,
            },
            x => todo!("Load sql data type: {}", x),
        }
    }))
}

async fn root(pool: SqlitePool, mut req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let mut resp = Response::default();
    let mut cont_ptr: usize = 0;

    unsafe {
        let size = roc_main_size();
        stackalloc::alloca(size, |buffer| {
            roc_main(buffer.as_mut_ptr() as *mut u8, &req);

            call_Continuation(
                // This flags pointer will never get dereferenced
                MaybeUninit::uninit().as_ptr(),
                buffer.as_ptr() as *const u8,
                &mut cont_ptr,
            );
        });
        loop {
            match get_tag(cont_ptr) {
                0 => {
                    // DBFetchOne
                    let untagged_ptr = remove_tag(cont_ptr);
                    let query_ptr = untagged_ptr;
                    let bind_params_ptr = untagged_ptr + std::mem::size_of::<RocStr>();

                    let mut query = sqlx::query((&*(query_ptr as *const RocStr)).as_str());
                    for data in (&*(bind_params_ptr as *const RocList<SqlData>)).iter() {
                        match data.discriminant() {
                            discriminant_SqlData::Int => query = query.bind(data.as_Int()),
                            x => todo!("Bind param type: {:?}", x),
                        }
                    }
                    let row = query
                        .fetch_one(&pool)
                        .await
                        .map(translate_row)
                        .map_err(|_err| SqlError::QueryFailed);
                    let row = RocResult::from(row);
                    log::debug!("{:?}", &row);

                    // Need to drop pointed to data that Roc returned to us.
                    std::ptr::drop_in_place(query_ptr as *mut RocStr);
                    std::ptr::drop_in_place(bind_params_ptr as *mut RocList<SqlData>);
                    cont_ptr = call_DBFetchOneCont_closure(cont_ptr, row);
                }
                1 => {
                    // LoadBody
                    // We steal the body and replace it with an empty body.
                    // Future calls to this method will get an empty string.
                    let mut tmp_body = Body::from("");
                    std::mem::swap(&mut tmp_body, req.body_mut());
                    let result = match hyper::body::to_bytes(tmp_body).await {
                        Ok(bytes) => RocResult::ok(RocStr::from_slice_unchecked(&bytes)),
                        _ => RocResult::err(()),
                    };
                    cont_ptr = call_LoadBodyCont_closure(cont_ptr, result);
                }
                2 => {
                    // Response
                    let out_ptr = remove_tag(cont_ptr) as *mut RocResponse;
                    *resp.status_mut() = StatusCode::from_u16((&*out_ptr).status)
                        .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
                    // TODO: Look into directly supporting RocStr here to avoid the copy.
                    *resp.body_mut() = Body::from((&*out_ptr).body.as_str().to_owned());
                    let header_map = resp.headers_mut();
                    for RocHeader { k, v } in (&*out_ptr).headers.iter() {
                        match HeaderValue::from_str(v.as_str()) {
                            Ok(v) => {
                                header_map.insert(k.as_str(), v);
                            }
                            Err(e) => {
                                log::error!(
                                    "Got invalid header value {} with error {:?}...ignoring",
                                    v,
                                    e
                                );
                            }
                        }
                    }

                    // Need to drop pointed to data that Roc returned to us.
                    std::ptr::drop_in_place(out_ptr);
                    break;
                }
                _ => {
                    *resp.status_mut() = StatusCode::INTERNAL_SERVER_ERROR;
                    break;
                }
            }
        }
        deallocate_refcounted_tag(cont_ptr);
    }

    Ok(resp)
}

unsafe fn call_DBFetchOneCont_closure(
    args_and_data_ptr: usize,
    row: RocResult<RocList<SqlData>, SqlError>,
) -> usize {
    let closure_data_ptr = remove_tag(
        args_and_data_ptr + std::mem::size_of::<RocStr>() + std::mem::size_of::<RocList<SqlData>>(),
    );
    let mut cont_ptr: usize = 0;

    call_DBFetchOneCont(&row, closure_data_ptr as *const u8, &mut cont_ptr);
    deallocate_refcounted_tag(args_and_data_ptr);

    std::mem::forget(row);

    cont_ptr
}

unsafe fn call_LoadBodyCont_closure(data_ptr: usize, result: RocResult<RocStr, ()>) -> usize {
    let closure_data_ptr = remove_tag(data_ptr);
    let mut cont_ptr: usize = 0;

    call_LoadBodyCont(&result, closure_data_ptr as *const u8, &mut cont_ptr);
    deallocate_refcounted_tag(data_ptr);

    std::mem::forget(result);

    cont_ptr
}

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    dotenvy::dotenv().ok();
    pretty_env_logger::init();

    assert_eq!(
        unsafe { call_Continuation_result_size() },
        std::mem::size_of::<*const c_void>()
    );
    assert!(unsafe { call_DBFetchOneCont_result_size() } <= std::mem::size_of::<*const c_void>());
    assert!(unsafe { call_LoadBodyCont_result_size() } <= std::mem::size_of::<*const c_void>());
    unsafe {
        RT = MaybeUninit::new(
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .unwrap(),
        );
        RT.assume_init_ref().block_on(async {
            let pool = SqlitePoolOptions::new()
                .max_connections(20)
                .connect(
                    &std::env::var("DATABASE_URL")
                        .expect("failed to load DATABASE_URL environment variable"),
                )
                .await
                .expect("failed to connect to database");
            // For every connection, we must make a `Service` to handle all
            // incoming HTTP requests on said connection.
            let make_svc = make_service_fn(move |_conn| {
                // This is the `Service` that will handle the connection.
                // `service_fn` is a helper to convert a function that
                // returns a Response into a `Service`.

                // Pool is meant to be cloned to a handler and should be cheap to clone here.
                let pool = pool.clone();
                async { Ok::<_, Infallible>(service_fn(move |req| root(pool.clone(), req))) }
            });
            let addr = ([0, 0, 0, 0], 3000).into();

            let server = Server::bind(&addr).serve(make_svc);

            log::info!("Listening on http://{}", addr);
            // Run this server for... forever!
            if let Err(e) = server.await {
                log::error!("server error: {}", e);
            }
        });
    }
    // Exit code
    0
}

#[repr(C)]
pub enum RocMethod {
    Connect,
    Delete,
    Get,
    Head,
    Options,
    Other,
    Patch,
    Post,
    Put,
    Trace,
}

#[no_mangle]
pub extern "C" fn roc_fx_method(req: *const Request<Body>) -> RocMethod {
    match unsafe { &*req }.method() {
        &Method::CONNECT => RocMethod::Connect,
        &Method::DELETE => RocMethod::Delete,
        &Method::GET => RocMethod::Get,
        &Method::HEAD => RocMethod::Head,
        &Method::OPTIONS => RocMethod::Options,
        &Method::PATCH => RocMethod::Patch,
        &Method::POST => RocMethod::Post,
        &Method::PUT => RocMethod::Put,
        &Method::TRACE => RocMethod::Trace,
        _ => RocMethod::Other,
    }
}

#[no_mangle]
pub unsafe extern "C" fn roc_fx_path(req: *const Request<Body>) -> RocStr {
    RocStr::from_slice_unchecked((&*req).uri().path().as_bytes())
}

// TODO: make this work somehow?
// The issue is that we can't take ownership of the body to read it.
// #[no_mangle]
// pub unsafe extern "C" fn roc_fx_body(req_usize: usize) -> TraitObject {
//     use hyper::body::HttpBody;
//     let ptr: BodyFuturePtr = Box::into_raw(Box::new(async move {
//         let req = req_usize as *const Request<Body>;
//         match hyper::body::to_bytes((&*req).into_body().boxed()).await {
//             Ok(bytes) => RocResult::ok(RocStr::from_slice_unchecked(&bytes)),
//             _ => RocResult::err(()),
//         }
//     }));
//     unsafe { std::mem::transmute(ptr) }
// }

unsafe fn deallocate_refcounted_tag(ptr: usize) {
    // TODO: handle this better.
    // To deallocate we first need to ignore the lower bits that include the tag.
    // Then we subtract 8 to get the refcount.
    let ptr_to_refcount = (remove_tag(ptr) - 8) as *mut c_void;
    roc_dealloc(ptr_to_refcount, 8);
}

fn get_tag(ptr: usize) -> u8 {
    ptr as u8 & 0x07
}

unsafe fn remove_tag(ptr: usize) -> usize {
    // TODO: is this correct always?
    ptr & 0xFFFF_FFFF_FFFF_FFF8
}
