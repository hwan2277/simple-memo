import {uuid} from './model.js';
import {sample} from './model.js';
const KEY='simple-memo-v2-demo';
export class DemoStore{
 constructor(){this.user={id:'demo'};try{this.data=JSON.parse(localStorage.getItem(KEY))||sample()}catch{throw Error('체험 데이터를 읽지 못했습니다. 브라우저 저장 공간을 확인해 주세요.')}}
 async load(){return structuredClone(this.data)}
 persist(){localStorage.setItem(KEY,JSON.stringify(this.data))}
 async saveMemo(m,version){const old=this.data.memos.find(x=>x.id===m.id);if(old&&old.version!==version)throw Error('다른 창에서 수정되었습니다. 새로고침 후 다시 확인해 주세요.');const saved={...m,version:(old?.version||0)+1,updated_at:new Date().toISOString()};this.data.memos=this.data.memos.filter(x=>x.id!==m.id).concat(saved);this.persist();return structuredClone(saved)}
 async removeMemo(id){this.data.memos=this.data.memos.filter(x=>x.id!==id);this.data.tasks=this.data.tasks.filter(x=>x.memo_id!==id);this.persist()}
 async folder(name,id){if(id){this.data.folders=this.data.folders.filter(f=>f.id!==id);this.data.memos.forEach(m=>{if(m.folder_id===id)m.folder_id=null})}else this.data.folders.push({id:uuid(),name});this.persist()}
 async renameFolder(id,name){const f=this.data.folders.find(f=>f.id===id);if(f)f.name=name;this.persist()}
 async tag(name,next){this.data.memos.forEach(m=>m.tags=[...new Set((m.tags||[]).flatMap(t=>t===name?(next?[next]:[]):[t]))]);this.persist()}
 async task(t,remove=false){this.data.tasks=this.data.tasks.filter(x=>x.id!==t.id);if(!remove)this.data.tasks.push(t);this.persist()}
}
export class CloudStore{
 constructor(sb,user){this.sb=sb;this.user=user}
 async check(result){if(result.error)throw result.error;return result.data}
 async load(){const fetchAll=async(table,select='*')=>{let out=[];for(let from=0;;from+=500){const rows=await this.check(await this.sb.from(table).select(select).order('id').range(from,from+499));out.push(...rows);if(rows.length<500)return out}};const [memos,folders,tasks]=await Promise.all([fetchAll('memos','*,memo_tags(tags(name))'),fetchAll('folders'),fetchAll('tasks')]);return {memos:memos.map(({memo_tags,...m})=>({...m,tags:(memo_tags||[]).map(x=>x.tags?.name).filter(Boolean)})),folders,tasks}}
 async saveMemo(m,version){const {data,error}=await this.sb.rpc('save_memo_v2',{p_id:m.id,p_version:version||0,p_title:m.title,p_content:m.content,p_folder_id:m.folder_id||null,p_color:m.color,p_pinned:m.is_pinned,p_favorite:m.is_favorite,p_archived:m.archived_at,p_deleted:m.deleted_at,p_tags:m.tags||[]});if(error)throw error;return {...data,tags:m.tags||[]}}
 async removeMemo(id){await this.check(await this.sb.from('memos').delete().eq('id',id).eq('user_id',this.user.id))}
 async folder(name,id){if(id)await this.check(await this.sb.from('folders').delete().eq('id',id));else await this.check(await this.sb.from('folders').insert({name,user_id:this.user.id}))}
 async renameFolder(id,name){await this.check(await this.sb.from('folders').update({name}).eq('id',id))}
 async tag(name,next){if(next)await this.check(await this.sb.from('tags').update({name:next}).eq('name',name));else await this.check(await this.sb.from('tags').delete().eq('name',name))}
 async task(t,remove=false){if(remove)await this.check(await this.sb.from('tasks').delete().eq('id',t.id));else await this.check(await this.sb.from('tasks').upsert({...t,user_id:this.user.id}))}
}
