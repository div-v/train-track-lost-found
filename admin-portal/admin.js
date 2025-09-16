// Firebase web config (replace with your own if needed)
const firebaseConfig = {
  apiKey: "AIzaSyC3al4PZFlkFtSPLVTyFgRG1zM_tye2A_M",
  authDomain: "logindb-c1c82.firebaseapp.com",
  databaseURL: "https://logindb-c1c82-default-rtdb.firebaseio.com",
  projectId: "logindb-c1c82",
  storageBucket: "logindb-c1c82.firebasestorage.app",
  messagingSenderId: "756173313023",
  appId: "1:756173313023:web:1e501004fc4304863fcdca"
};

// Initialize compat
firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();
const db = firebase.firestore();

// State
let currentUser = null;
let currentClaims = null;
let lastDoc = null;
let firstDoc = null;
let page = 1;
let pageSize = 10;
let cursorStack = [];

// DOM helpers
const el = (id)=>document.getElementById(id);
const toast = (msg)=>{
  const t = el('toast'); t.textContent = msg; t.classList.remove('hidden');
  setTimeout(()=>t.classList.add('hidden'), 2600);
};
const setChipsActive = (containerId, value)=>{
  const chips = document.querySelectorAll('#'+containerId+' .chip');
  chips.forEach(c=>c.classList.toggle('active', c.dataset.value === value));
};

// Auth
async function signInWithGoogle(){
  const provider = new firebase.auth.GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  try{
    const res = await auth.signInWithPopup(provider);
    return res.user;
  }catch(err){
    console.error('Google sign-in error', err);
    const msg = (err && err.message) ? err.message : 'Check provider enabled and authorized domain.';
    toast('Google sign-in failed: ' + msg);
    throw err;
  }
}

async function refreshClaims(user){
  if(!user) return null;
  await user.getIdToken(true);
  const idTokenResult = await user.getIdTokenResult();
  return idTokenResult.claims || {};
}
function isStaff(){
  return currentClaims && (currentClaims.role === 'admin' || currentClaims.role === 'mod');
}

// Filters
function readFilters(){
  const type = document.querySelector('#typeChips .chip.active')?.dataset.value || 'all';
  return {
    q: el('q').value.trim().toLowerCase(),
    type,
    category: el('category').value,
    status: el('status').value,
    station: el('station').value.trim().toLowerCase(),
    dateStr: el('dateStr').value.trim(),
  };
}
function clearFilters(){
  el('q').value = '';
  setChipsActive('typeChips','all');
  el('category').value = 'All';
  el('status').value = 'any';
  el('station').value = '';
  el('dateStr').value = '';
}

// Query
function baseQuery(){
  return db.collection('items').orderBy('timestamp','desc');
}

async function fetchPage(direction='next'){
  const filters = readFilters();
  let q = baseQuery();

  if(filters.status !== 'any'){
    q = q.where('status','==',filters.status);
  }
  if(filters.type !== 'all'){
    q = q.where('type','==',filters.type);
  }

  q = q.limit(pageSize);
  if(direction === 'next' && lastDoc){
    q = q.startAfter(lastDoc);
  }
  if(direction === 'prev'){
    cursorStack.pop();
    const prevCursor = cursorStack[cursorStack.length-1];
    if(prevCursor){
      q = q.startAt(prevCursor);
    } else {
      page = 1;
    }
  }

  const snap = await q.get();
  if(snap.empty){
    return {docs: [], first: null, last: null};
  }

  const docs = snap.docs.map(d=>({id:d.id, ...d.data()}));

  // client-side filter
  const s = filters.q;
  let filtered = docs.filter(item=>{
    if(filters.category !== 'All' && item.category !== filters.category) return false;
    if(filters.station && !(item.stationOrTrain||'').toString().toLowerCase().includes(filters.station)) return false;
    if(filters.dateStr && (item.date_str_norm||'') !== filters.dateStr) return false;
    if(s){
      const hay = ((item.title||'') + ' ' + (item.description||'') + ' ' + (item.stationOrTrain||'')).toLowerCase();
      if(!hay.includes(s)) return false;
    }
    return true;
  });

  firstDoc = snap.docs[0];
  lastDoc = snap.docs[snap.docs.length-1];
  if(direction==='next'){
    cursorStack.push(firstDoc);
    page++;
  } else if(direction==='prev') {
    page = Math.max(1, page-1);
  }

  return {docs: filtered, first:firstDoc, last:lastDoc};
}

// Render
function statusBadge(status){
  const map = {
    active: 'badge active',
    flagged: 'badge flagged',
    claimed: 'badge claimed',
    deleted: 'badge deleted'
  };
  const cls = map[status] || 'badge';
  return `<span class="${cls}">${status||'unknown'}</span>`;
}

function escapeHtml(s){
  return (s||'').toString()
    .replaceAll('&','&amp;')
    .replaceAll('<','&lt;')
    .replaceAll('>','&gt;')
    .replaceAll('"','&quot;')
    .replaceAll("'",'&#039;');
}

function itemCard(item){
  const dateText = item.date && item.date.toDate
    ? item.date.toDate().toISOString().split('T')[0]
    : (item.date||'').toString().split('T')[0];

  const email = (item.postedByEmail ?? '').toString().trim();
  const safeEmail = email.replace(/["'<>]/g, '');

  return `
    <div class="card item-card">
      <img class="item-img" src="${item.photoUrl||''}" alt="">
      <div class="item-body">
        <div class="row">
          <div class="grow">
            <div class="item-title">${escapeHtml(item.title||'')}</div>
            <div class="muted desc">
              ${escapeHtml((item.description||'').toString().length>140
                ? (item.description||'').toString().slice(0,140)+'…'
                : (item.description||''))}
            </div>
            <div class="row between">
              <span class="muted">Train/Station: ${escapeHtml(item.stationOrTrain||'-')}</span>
              <span class="muted">${dateText}</span>
            </div>
            <div class="badge-row">
              <span class="badge active">${escapeHtml(item.type||'-')}</span>
              ${statusBadge(item.status||'active')}
              <span class="badge gray">${escapeHtml(item.category||'-')}</span>
            </div>
          </div>
        </div>
        <div class="actions">
          <div class="actions-left">
            <button class="btn ok" data-action="claim" data-id="${item.id}">Mark Claimed</button>
            <button class="btn" data-action="flag" data-id="${item.id}">Flag</button>
            <button class="btn danger" data-action="delete" data-id="${item.id}">Delete</button>
          </div>
          <div class="actions-right">
            <button class="btn" data-action="email" data-email="${safeEmail}">
            <img src="https://www.gstatic.com/images/branding/product/1x/gmail_48dp.png" 
            alt="Gmail" width="18" height="18" class="icon-img">       
              Contact Poster
            </button>
            ${item.photoUrl ? `<a class="btn" href="${item.photoUrl}" target="_blank">View Image</a>`:''}
          </div>
        </div>
      </div>
    </div>
  `;
}

function renderList(items){
  const grid = document.getElementById('grid');
  grid.innerHTML = items.map(itemCard).join('');
  // Re-bind after every render
  grid.querySelectorAll('button[data-action]').forEach(btn=>{
    btn.addEventListener('click', onActionClick, { passive: true });
  });
  document.getElementById('pageInfo').textContent = `Page ${Math.max(page,1)}`;
}

// Audit + actions
async function writeAudit(postId, action, extra={}){
  const now = firebase.firestore.FieldValue.serverTimestamp();
  const payload = {
    postId, action,
    actorUid: currentUser.uid,
    actorEmail: currentUser.email||'',
    actorRole: currentClaims.role||'',
    ts: now,
    ...extra
  };
  await db.collection('moderation_events').add(payload);
}

async function markClaimed(id){
  const ref = db.collection('items').doc(id);
  await db.runTransaction(async (tx)=>{
    const snap = await tx.get(ref);
    if(!snap.exists) throw new Error('Not found');
    const before = snap.data();
    tx.update(ref, { status:'claimed', claimedBy: currentUser.uid });
    setTimeout(()=>writeAudit(id, 'mark_claimed', { oldStatus: before.status||'active', newStatus:'claimed' }), 0);
  });
  toast('Marked as claimed');
}

async function hardDelete(id){
  const ref = db.collection('items').doc(id);
  const snap = await ref.get();
  if(!snap.exists) throw new Error('Not found');
  const before = snap.data();
  await ref.delete();
  await writeAudit(id, 'hard_delete', { oldStatus: before.status||'active', newStatus:'deleted_from_db' });
  toast('Item permanently deleted');
}

async function flagItem(id){
  const ref = db.collection('items').doc(id);
  await db.runTransaction(async (tx)=>{
    const snap = await tx.get(ref);
    if(!snap.exists) throw new Error('Not found');
    const before = snap.data();
    tx.update(ref, { status:'flagged' });
    setTimeout(()=>writeAudit(id, 'flag', { oldStatus: before.status||'active', newStatus:'flagged' }), 0);
  });
  toast('Item flagged');
}

// Email open helper (same-tab navigation)
function openEmailDraft(email){
  const addr = (email || '').trim();
  if(!addr){ toast('No email on file'); return; }

  const subject = encodeURIComponent('Regarding your Lost & Found post');
  const body = encodeURIComponent('Hello,\n\nThis is regarding your post on TrainTrack Lost & Found.\n\n— Staff');
  const href = `mailto:${encodeURIComponent(addr)}?subject=${subject}&body=${body}`;

  // Most reliable across Chrome/Edge/Firefox
  window.location.assign(href);
}

async function onActionClick(e){
  const id = e.currentTarget.dataset.id;
  const action = e.currentTarget.dataset.action;

  if(action === 'email'){
    const email = (e.currentTarget.dataset.email || '').trim();
    openEmailDraft(email);
    return;
  }

  if(!isStaff()){
    toast('Permission denied');
    return;
  }
  try{
    if(action==='claim') await markClaimed(id);
    if(action==='delete') await hardDelete(id);
    if(action==='flag') await flagItem(id);
    const {docs} = await fetchPage('stay');
    renderList(docs);
  }catch(err){
    console.error(err);
    toast('Action failed: ' + (err.message||''));
  }
}

// Events
document.getElementById('btnSignIn').addEventListener('click', async ()=>{
  try { await signInWithGoogle(); } catch(e) {}
});
document.getElementById('btnSignOut').addEventListener('click', async ()=>{
  await auth.signOut();
});
document.getElementById('btnApply').addEventListener('click', async ()=>{
  page = 0; lastDoc = null; firstDoc = null; cursorStack = [];
  const {docs} = await fetchPage('next'); renderList(docs);
});
document.getElementById('btnClear').addEventListener('click', async ()=>{
  clearFilters(); page = 0; lastDoc = null; firstDoc = null; cursorStack = [];
  const {docs} = await fetchPage('next'); renderList(docs);
});
document.getElementById('nextPage').addEventListener('click', async ()=>{
  const {docs} = await fetchPage('next');
  if(docs.length===0){ toast('No more items'); page--; return; }
  renderList(docs);
});
document.getElementById('prevPage').addEventListener('click', async ()=>{
  if(page<=1){ toast('Already at first page'); return; }
  const {docs} = await fetchPage('prev'); renderList(docs);
});
document.getElementById('pageSize').addEventListener('change', async (e)=>{
  pageSize = parseInt(e.target.value,10)||10;
  page = 0; lastDoc = null; firstDoc = null; cursorStack = [];
  const {docs} = await fetchPage('next'); renderList(docs);
});
document.querySelectorAll('#typeChips .chip').forEach(ch=>{
  ch.addEventListener('click', ()=>{
    document.querySelectorAll('#typeChips .chip').forEach(c=>c.classList.remove('active'));
    ch.classList.add('active');
  });
});

auth.onAuthStateChanged(async (user)=>{
  currentUser = user;
  const signedIn = !!user;
  el('btnSignIn').classList.toggle('hidden', signedIn);
  el('btnSignOut').classList.toggle('hidden', !signedIn);
  el('userEmail').textContent = user ? user.email : '';

  if(user){
    currentClaims = await refreshClaims(user);
    if(!isStaff()){
      toast('Access restricted to staff');
      document.getElementById('grid').innerHTML = '';
      return;
    }
    page = 0; lastDoc = null; firstDoc = null; cursorStack = [];
    const {docs} = await fetchPage('next'); renderList(docs);
  } else {
    document.getElementById('grid').innerHTML = '';
  }
});
