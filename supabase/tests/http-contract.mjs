// Isolated localhost integration check. Credentials stay in memory and are never logged.
import {execFileSync} from 'node:child_process';
import {createHmac, randomUUID, randomBytes} from 'node:crypto';
const url = 'http://127.0.0.1:54321';
const secret = execFileSync('docker',['exec','supabase_auth_Memory-minimalist-review','printenv','GOTRUE_JWT_SECRET'],{encoding:'utf8'}).trim();
const jwt = role => {
  const head = Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');
  const body = Buffer.from(JSON.stringify({role,iss:'supabase',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+600})).toString('base64url');
  return `${head}.${body}.${createHmac('sha256',secret).update(`${head}.${body}`).digest('base64url')}`;
};
const admin = jwt('service_role'), anon = jwt('anon'), users = [], deck = `http-test-${randomUUID()}`;
let socket;
async function request(path,token,body,method = body === undefined ? 'GET' : 'POST',expected = 200) {
  const response = await fetch(url+path,{method,headers:{apikey:anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body === undefined ? undefined : JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const value = await response.json().catch(()=>null);
  if (response.status !== expected) throw new Error(`${path}: expected ${expected}, received ${response.status}`);
  return value;
}
function assert(value,message) { if (!value) throw new Error(message); }
const op = (kind,id,version,content,deleted = false) => ({operation_id:randomUUID(),entity_kind:kind,entity_id:id,target_deck:kind==='private'?null:deck,base_version:version,content,is_deleted:deleted});
try {
  for (const label of ['owner','editor']) {
    const email = `${label}-${randomUUID()}@engram.test`, password = randomBytes(24).toString('base64url');
    const created = await request('/auth/v1/admin/users',admin,{email,password,email_confirm:true});
    users.push({id:created.id});
    const session = await request('/auth/v1/token?grant_type=password',anon,{email,password});
    users.at(-1).token = session.access_token;
  }
  const [owner,editor] = users, apply = (user,operation) => request('/rest/v1/rpc/engram_apply',user.token,operation);
  assert((await apply(owner,op('deck',deck,0,{id:deck,name:'HTTP integration'}))).status==='saved','Deck create failed');
  const note = `${deck}-note`, original = op('note',note,0,{id:note,deckID:deck,kind:'basic',front:'Energy?',back:'ATP',tags:[],source:'',deleted:false,modifiedAt:0});
  assert((await apply(owner,original)).version===1,'Note create failed');
  assert((await apply(owner,original)).version===1,'Retry repeated mutation');
  await apply(owner,op('private',`${owner.id}:attempt:one`,0,{category:'attempt',id:'one',deckID:deck,value:{answer:'Owner private'}}));
  const invite = await request('/rest/v1/rpc/engram_invite',owner.token,{target_deck:deck,member_role:'editor',valid_hours:1});
  assert(await request('/rest/v1/rpc/engram_accept',editor.token,{invitation_token:invite.token})===deck,'Invite failed');
  const rows = await request(`/rest/v1/engram_entities?deck_id=eq.${deck}`,editor.token);
  assert(rows.length===2 && rows.every(x=>x.kind!=='private'),'Shared scope exposed private attempt');
  assert((await request('/rest/v1/engram_entities?kind=eq.private',editor.token)).length===0,'Private attempt exposed');
  const notifications = [];
  socket = new WebSocket(`ws://127.0.0.1:54321/realtime/v1/websocket?apikey=${anon}&vsn=1.0.0`);
  await new Promise((resolve,reject)=> {
    const timer = setTimeout(()=>reject(new Error('Local Realtime subscription timed out')),5000);
    socket.addEventListener('open',()=>socket.send(JSON.stringify({topic:'realtime:engram-http-test',event:'phx_join',ref:'1',payload:{access_token:editor.token,config:{postgres_changes:[{event:'INSERT',schema:'public',table:'engram_changes'}]}}})));
    socket.addEventListener('message',event=> {
      const message = JSON.parse(String(event.data));
      if (message.event==='postgres_changes') notifications.push(message.payload.data.record);
      if (message.event==='phx_reply' && message.ref==='1' && message.payload.status!=='ok') { clearTimeout(timer); reject(new Error('Local Realtime subscription rejected')); }
      if (message.event==='system' && message.payload.status==='ok') { clearTimeout(timer); resolve(); }
    });
    socket.addEventListener('error',()=> { clearTimeout(timer); reject(new Error('Local Realtime unavailable')); });
  });
  assert((await apply(editor,op('note',note,1,{...original.content,front:'Cellular energy?'}))).version===2,'Editor update failed');
  await apply(owner,op('private',`${owner.id}:memory:one`,0,{category:'memory',id:'one',deckID:deck,value:{text:'Owner private correction'}}));
  await new Promise(resolve=>setTimeout(resolve,1500));
  assert(notifications.some(x=>x.entity_id===note),'Authorized Realtime hint missing');
  assert(notifications.every(x=>x.kind!=='private'),'Realtime exposed private learner state');
  assert((await apply(owner,op('note',note,1,{...original.content,back:'Wrong stale value'}))).status==='conflict','Stale edit accepted');
  await request('/rest/v1/rpc/engram_revoke',owner.token,{target_deck:deck,member_user:editor.id,invitation_id:null},'POST',204);
  assert((await request(`/rest/v1/engram_entities?deck_id=eq.${deck}`,editor.token)).length===0,'Revoked cache still downloadable');
  await request('/rest/v1/rpc/engram_apply',editor.token,op('note',note,2,original.content),'POST',400);
  const remove = op('deck',deck,1,{id:deck,name:'Deleted',deleted:true},true);
  await apply(owner,remove); assert((await apply(owner,remove)).version===2,'Owner deletion retry failed');
  assert((await apply(owner,op('deck',deck,2,{id:deck,name:'Restored',deleted:false}))).version===3,'Owner restoration failed');
  console.log('PASS: localhost Auth, RPC encoding, two-user sharing, private isolation including Realtime, CAS, revocation and owner recovery. No hosted pilot enabled.');
} finally {
  socket?.close();
  const ids = users.map(x=>x.id);
  if (ids.every(id=>/^[0-9a-f-]{36}$/.test(id))) {
    const sql = `begin; delete from engram_private.invitations where deck_id='${deck}'; delete from engram_private.operations where user_id in (${ids.map(id=>`'${id}'`).join(',') || "null"}); delete from public.engram_changes where deck_id='${deck}' or learner_id in (${ids.map(id=>`'${id}'`).join(',') || "null"}); delete from public.engram_entities where deck_id='${deck}' or learner_id in (${ids.map(id=>`'${id}'`).join(',') || "null"}); delete from public.engram_members where deck_id='${deck}'; delete from public.engram_decks where id='${deck}'; commit;`;
    execFileSync('docker',['exec','-i','supabase_db_Memory-minimalist-review','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','ignore','pipe']});
    for (const user of users) await request(`/auth/v1/admin/users/${user.id}`,admin,undefined,'DELETE');
  }
}
