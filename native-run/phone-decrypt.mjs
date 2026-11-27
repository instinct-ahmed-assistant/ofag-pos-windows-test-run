// Independent decrypt check (Node WebCrypto): AES-256-GCM, AAD = token. Reads the pairing code file and the document fetched back from the server. Synthetic data only.
import {readFileSync} from 'node:fs';import {webcrypto as c} from 'node:crypto';
const code=readFileSync(process.argv[2],'utf8').trim();const doc=JSON.parse(readFileSync(process.argv[3],'utf8').replace(/^\uFEFF/,''));
const [pre,token,k]=code.split('.');
const b=s=>Buffer.from(s.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(s.length/4)*4,'='),'base64');
const f=doc.fields;const key=await c.subtle.importKey('raw',b(k),'AES-GCM',false,['decrypt']);
const pt=await c.subtle.decrypt({name:'AES-GCM',iv:Buffer.from(f.n.stringValue,'base64'),additionalData:Buffer.from(token),tagLength:128},key,Buffer.from(f.c.stringValue,'base64'));
const out=Buffer.from(pt).toString('utf8');const j=JSON.parse(out);
const keys=Object.keys(j).sort().join(',');
console.log('NODE DECRYPT OK keys='+keys+' asOf='+j.asOf+' shift='+j.shift+' sales='+JSON.stringify(j.sales)+' low='+j.low.length+' expiring='+j.expiring.length);
const need='asOf,branch,expiring,low,payments,sales,shift,shifts,top'.split(',');const miss=need.filter(k=>!(k in j));if(miss.length){console.log('FAIL missing fields '+miss.join(','));process.exit(1)}console.log('EXTRA fields (allowed): '+Object.keys(j).filter(k=>!need.includes(k)).join(',')); 
console.log('SAMPLE '+out.slice(0,300));
