package db;

using Lambda;

// representing a database scheme

enum DBToolFieldType {
  db_varchar( length: Int );
  db_bool;
  db_int;
  db_enum( valid_items: List<String> );
  db_date;
  db_text; // text field. arbitrary length. Maybe no indexing and slow searching

  // store ints instead of the named Enum. Provide getter and setters for enum
  // values. Take care when remving or replacing enum values. You have to
  // adjust the inedxes then
  db_haxe_enum_simple_as_index(e:String);
}

enum DBEither<A,B> {
  db_left(x:A);
  db_right(x:B);
}

// supported databases
enum DBSupportedDatabaseType {
  db_mysql;
  db_postgres;
  // db_sqlite;
}

interface IDBSerializable {
  function toString():String;
}

class DBHelper {
  static public function concatArrays<T>(lists:List<Array<T>>): Array<T> {
    return lists.fold(function(a,b){return a.concat(b);}, []);
  }
  static public inline function assert(b:Bool, msg:String){ if (!b) throw msg; }
  static public function sep(o:Array<Dynamic>, n:Array<Dynamic>)
  :{o: List<Dynamic>, k: List<{o: Dynamic, n:Dynamic}>, n: List<Dynamic>}
    {
    var processed = new Hash();

    var old = new List();
    var keep = new List();
    var new_ = new List();

    var hash = new Hash();
    for (o_ in o) hash.set(o_.name, o_);

    for (n_ in n){
      if (hash.exists(n_.name)){
        keep.add( {o: hash.get(n_.name), n: n_} );
        hash.remove(n_.name);
      } else 
        new_.add(n_);
    }
    return { o: hash.list(), k: keep, n: new_};
  }
}

class DBFieldDecorator {

  public function decorate(db: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, droppingTable: Bool):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    throw "abstract method: DBFieldDecorator.decorate";
    return {
      extraFieldText: "",
      sql_before: [],
      sql_after: [],
      sql_remove: [],
    }
  }

  static public function merge(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, decorators: Array<DBFieldDecorator>, droppingTable:Bool){
    var decorateList   = decorators.map(function(d){ return d.decorate(db_,  type, tableName, field, droppingTable); });
    return{
      extraFieldText  : decorateList.map(function(d){ return d.extraFieldText; }).join(" "),
      sql_before      : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_before; })),
      sql_after       : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_after; })),
      sql_remove      : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_remove; }))
    }
  }

}


class DBFDComment extends DBFieldDecorator {
  var __comment: String;

  public function new(comment:String) {
    __comment = comment;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, droppingTable: Bool):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    // TODO quoting
    switch (db_){
      case db_postgres:
        return {
          extraFieldText : "COMMENT \""+__comment+"\"",
          sql_before : [],
          sql_after: [],
          sql_remove: []

        }
      case db_mysql:
        return {
          extraFieldText : "COMMENT \""+__comment+"\"",
          sql_before : [],
          sql_after: [],
          sql_remove: []
        }
    }
  }
}


class DBFDIndex extends DBFieldDecorator {
  public var __uniq: Bool;

  public function new(?uniq:Bool) {
    __uniq = uniq;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, droppingTable: Bool):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    var index_name = "index_"+tableName+"_"+field;
    switch (db_){
      case db_postgres:
        return {
          extraFieldText : "",
          sql_before : [],
          sql_after: ["CREATE "+(__uniq ? "UNIQUE" : "" )+" INDEX "+index_name+" ON "+tableName+"("+field+")"],
          // if field was dropped index does no longer exist
          sql_remove: droppingTable ? [] : ["DROP INDEX IF EXISTS "+index_name]

        }
      case db_mysql:
        return {
          extraFieldText : "",
          sql_before : [],
          sql_after: ["CREATE "+(__uniq ? "UNIQUE" : "" )+" INDEX "+index_name+" ON "+tableName+"("+field+")"],
          sql_remove: droppingTable ? [] : ["ALTER TABLE "+tableName+" DROP INDEX "+index_name]
        }
    }
  }
}


class DBFDAutoinc extends DBFieldDecorator {

  public function new() {
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, droppingTable: Bool):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    if (type != db_int)
      throw "DBFDAutoinc only supports db_int fields!";

    switch (db_){
      case db_postgres:
        var seq_name = "autoinc_sequence_"+tableName+"_"+field;
        return {
          extraFieldText : " DEFAULT nextval('"+seq_name+"') ",
          sql_before : ["CREATE SEQUENCE "+seq_name ],
          sql_after: [],
          sql_remove: ["DROP SEQUENCE "+seq_name ]

        }
      case db_mysql:
        return {
          extraFieldText : " auto_increment key ",
          sql_before : [],
          sql_after: [],
          sql_remove: []
        }
    }
      
  }

}

class DBFDCurrentTimestmap extends DBFieldDecorator {
  var __onInsert: Bool;
  var __onUpdate: Bool;

  // TODO implement this for MySQL. See comments in 
  // must use triggers for MySQL when using more than one column which should be updated.
  // However they are likely to cause problems
  // because you need root priviledges in order to set them up on hosting systems
  var __forcTriggers: Bool;

  public function new(){
  }

  public function onInsert(){
    __onInsert = true;
    return this;
  }

  public function onUpdate(){
    __onUpdate = true;
    return this;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, droppingTable:Bool):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    if (type != db_date)
      throw "DBFDCurrentTimestmap only supports db_date fields!";

    switch (db_){
      case db_postgres:

        var sql_remove = new Array();
        if (__onUpdate) {
          if (!droppingTable)
            sql_remove.push("DROP TRIGGER update_timestamp_"+tableName+"_"+field+"_trigger ON "+tableName);
          sql_remove.push("DROP FUNCTION update_timestamp_"+tableName+"_"+field+"()");
        }

        return {
          extraFieldText : __onInsert ? " default CURRENT_TIMESTAMP " : "",
          sql_before : [],
          sql_after: __onUpdate
                        ? ["
                          CREATE OR REPLACE FUNCTION update_timestamp_"+tableName+"_"+field+"() RETURNS TRIGGER 
                          LANGUAGE plpgsql
                          AS
                          $$
                          BEGIN
                              NEW."+field+" = CURRENT_TIMESTAMP;
                              RETURN NEW;
                          END;
                          $$;
                        ",
                        "
                          CREATE TRIGGER update_timestamp_"+tableName+"_"+field+"_trigger
                            BEFORE UPDATE
                            ON "+tableName+"
                            FOR EACH ROW
                            EXECUTE PROCEDURE update_timestamp_"+tableName+"_"+field+"();
                        "
                        ] : [],
          sql_remove: sql_remove

        }
      case db_mysql:
        return {
          extraFieldText : (__onInsert ? " default CURRENT_TIMESTAMP " : "")
                         + (__onUpdate ? " on update CURRENT_TIMESTAMP " : ""),
          sql_before : [],
          sql_after: [],
          sql_remove: []
        }
    }
      
  }

}


// represents a field
class DBField implements IDBSerializable {

  public var name: String;
  public var type: DBToolFieldType;
  public var __references: Null<{table: String, field: String}>;
  public var __nullable: Bool;


  public function decoratorsOftype(c:Class<Dynamic>):List<DBFieldDecorator>{
    return __decorators.filter(function(x){ return Std.is(x, c); });
  }

  // property __uniq {{{1
  // if this field is the only primary key its uniq as well - but this can only be known in the table
  public var __uniq(get__uniq, null) : Bool;
  private function get__uniq(): Bool {
    var l = decoratorsOftype(DBFDIndex).first();
    return l != null && cast(l,DBFDIndex).__uniq;
  }
  // }}}
  

  public var __decorators: Array<DBFieldDecorator>;

  // serialization {{{2
  // create object from serialized string
  public function toString() {
    return haxe.Serializer.run(this);
  }
  
  static function unserialize(s:String):DBField{
    // be careful if you change the items
    // Here is the place to implement backward compatibility !!
    return haxe.Unserializer.run(s);
  }
  // }}}

  public function new(name: String, type:DBToolFieldType, ?decorators:Array<DBFieldDecorator>){
    this.name = name;
    this.type = type;
    this.__nullable = false;
    __decorators = decorators == null ? [] : decorators;
    switch (type){
      case db_haxe_enum_simple_as_index(e):
        if (null == Type.resolveEnum(e))
          throw "invalid enum name "+e+" of field "+name;
      default:
    }
  }

  public function nullable(){
    __nullable = true;
    return this;
  }

  public function references(table: String, field:String) {
    this.__references = { table : table, field : field };
    return this;
  }

  public function indexed() {
    this.__decorators.push(new DBFDIndex(false));
    return this;
  }

  public function uniq() {
    this.__decorators.push(new DBFDIndex(true));
    return this;
  }

  public function autoinc() {
    this.__decorators.push(new DBFDAutoinc());
    return this;
  }

  function field(name:String, haxeType:String){
     return
       "  private var _"+name+": "+haxeType+";\n"+
       "  public var "+name+"(get"+name+", set"+name+") : "+haxeType+";\n"+
       "  private function get"+name+"(): "+haxeType+" {\n"+
       "     return _"+name+";\n"+
       "  }\n"+
       "  private function set"+name+"(value : "+haxeType+"): "+haxeType+" {\n"+
       "    if (value == _"+name+") return _"+name+";\n"+
       "    this.__dirty_data = true;\n"+
       "    return _"+name+" = value;\n"+
       "  }\n";
  }

  // defines the DB <-> HaXe interface for this type
  public function haxe(db: DBSupportedDatabaseType):{
    // the db field type (TODO not yet used. Refactor!)
    dbType: String,

    // the HaXe type to be used
    haxeType: String,

    // the "public var field: Field;" line
    // may also contain additional getter/ setter code (eg enum type)
    // also contains NAMEtoHaxe NAMEToDB which converts HaXe <-> db types
    // this is inlined id func except enum types and such
    spodCode: String

    // TODO add DB setup and teardown hooks. eg autoincrement for Postgres
  }
  {


    switch (type){
      case db_varchar(length):
        return {
          dbType:  "varchar("+length+")",
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"
        };
      case db_bool:
        return {
          dbType: "varchar(1)", // every db has varchar
          haxeType: "Bool",
          spodCode:
            field(name, "Bool")+
            "  static inline public function "+name+"ToHaXe(v: String):Bool { return (v == \"y\"); }\n"+ 
            "  static inline public function "+name+"ToDB(v: Bool):String { return v ? \"y\" : \"n\"; }\n"
        };
      case db_int:
        return {
          dbType: "Int",
          haxeType: "Int",
          spodCode:
            field(name, "Int")+
            "  static inline public function "+name+"ToHaXe(v: Int):Int { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: Int):Int { return v; }\n"

        };
      case db_enum(valid_items):
        return {
          dbType: "String",
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"
        };
      case db_date:
        // TODO
        return{ 
          dbType: "Date",
          haxeType: "Date",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"

        };
      case db_text:
        var dbType = switch (db){
          case db_postgres: "text";
          default: "text";
        }
        return {
          dbType: dbType,
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"

        };
      case db_haxe_enum_simple_as_index(e):
        var gt = "get"+name+"AsEnum";
        var st = "set"+name+"AsEnum";
        var tE = name+"toEnum";
        return {
          dbType: "int",
          haxeType: e,
          spodCode:
            field(name, "Int")+
            "  static inline public function "+name+"ToHaXe(i:Int):"+e+"{ return Type.createEnumIndex("+e+", i); }\n"+
            "  static inline public function "+name+"ToDB(v: "+e+"):Int { return Type.enumIndex(v); }\n"+
            // getter + setter
            "   public var "+name+"AsEnum("+gt+", "+st+") : "+e+";\n"+
            "   function "+gt+"():"+e+"{ return  "+name+"ToHaXe("+name+"); }\n"+
            "   function "+st+"(value : "+e+") :"+e+"{ "+name+" = "+name+"ToDB(value); return value; }\n"
        };
    }


  }

  static public function fieldCode(
      db_: DBSupportedDatabaseType,
      tableName: String,
      f: DBField,
      droppingTable:Bool
      ):{
        fields: Array<String>,     // fields to be inserted into a CREATE TABLE or ALTER TABLE XY CHANGE statement
        alter: Array<String>,       // string after ALTER TABLE xy ..
                                   // for mysql this is CHANGE ..
                                   // for postgresql this is more sophisticated
        fieldNames: Array<String>, // the names of the fields, so that ATLTER TABLE DROP FIELD .. can be generated
        sql_before: Array<String>, // SQL to setup triggers, sequences or whatnot
        sql_after : Array<String>, // same, but run after CREATE TABLE ..
        sql_remove : Array<String> // remove what sql_before, sql_after added to the database
    }{

    switch (db_){
      case db_postgres: // {{{
        var merged = DBFieldDecorator.merge(db_, f.type, tableName, f.name, f.__decorators, droppingTable);
        var nullable = (f.__nullable) ? "" : " NOT NULL ";

        var references = ( f.__references == null ) ? "": " REFERENCES " + f.__references.table + "("+ f.__references.field + ")";
        var field:Array<String>;
        var type:String; // TODO use Array

        switch (f.type){
          case db_varchar(length):
            type = "varchar("+length+")";
            field = [f.name+" "+type+ " " + nullable + merged.extraFieldText + references];
          case db_bool:
            type = "bool";
            field = [f.name+" "+type+" " + nullable +  merged.extraFieldText + references];
          case db_int:
            type = "int";
            field = [f.name+" "+ type + " " + nullable +  merged.extraFieldText + references];
          case db_enum(valid_items):
            var fun = function(x){ return "'"+x+"'"; };
            var enumTypeName = tableName+"_"+f.name;
            type = enumTypeName;
            field = [f.name+" "+type + " " + nullable +  merged.extraFieldText + references];
            merged.sql_before.push("CREATE TYPE "+enumTypeName+ " AS ENUM ("+valid_items.map(fun).join(",")+")");
          case db_date:
             type = "timestamp";
             field = [f.name+" "+type+" " + nullable + merged.extraFieldText + references];

          case db_text:
             type = "text";
            field = [f.name+" "+type+" " + nullable + merged.extraFieldText + references];

          case db_haxe_enum_simple_as_index(e):
            type = "int";
            field = [f.name+" "+type+" " + nullable +  merged.extraFieldText + references];
            var enumTypeName = tableName+"_"+f.name;
            var f = function(x){ return "'"+x+"'"; };
            merged.sql_remove.push("DROP TYPE "+enumTypeName);
        }

        var a = "ALTER "+f.name+" ";

        return {
          fields: field,
          // Postgresql has different syntax for changing the field type
          alter:  [ [a+"TYPE "+type, a+(f.__nullable ? "DROP NOT NULL" : "SET NOT NULL")].join(", ") ],
          fieldNames: [ f.name ],
          sql_before: merged.sql_before,
          sql_after : merged.sql_after,
          sql_remove : merged.sql_remove
        };
      // }}}
      case db_mysql: // {{{

        var merged = DBFieldDecorator.merge(db_, f.type, tableName, f.name, f.__decorators, droppingTable);
        var nullable = (f.__nullable) ? "" : " NOT NULL ";
        var references = ( f.__references == null ) ? "": " REFERENCES " + f.__references.table + "("+ f.__references.field + ")";
        var field:Array<String>;
        switch (f.type){
          case db_varchar(length):
            field = [f.name+" varchar("+length+")" + nullable + merged.extraFieldText + references];
          case db_bool:
             field = [f.name+" enum('y','n')"];
          case db_int:
            field = [f.name+" int" + nullable + merged.extraFieldText + references];
          case db_enum(valid_items):
            var fun = function(x){ return "'"+x+"'"; };
            field = [f.name+" enum("+ valid_items.map(fun).join(",") +")" + nullable + merged.extraFieldText + references];
          case db_date:
            field = [f.name+" timestamp " + nullable + merged.extraFieldText + references];
          case db_text:
            field = [f.name+" longtext" + nullable + merged.extraFieldText + references];
          case db_haxe_enum_simple_as_index(e):
            field = [f.name+" int" + nullable + merged.extraFieldText + references];
        }

        return {
          fields: field,
          alter: field.map(function(fx){ return "CHANGE "+f.name+" "+fx; }).array(),
          fieldNames: [ f.name ],
          sql_before : merged.sql_before,
          sql_after  : merged.sql_after,
          sql_remove : merged.sql_remove
        };
      // }}}
    }

  }


  // returns message if type can't be represented in a dabatase
  // sql_before : ""; sql_after may be required to satisfy constraints or do more (?) not implemented yet. Maybe removed again
  static public function toSQL(
      db_: DBSupportedDatabaseType,
      tableName: String,
      old: Null<DBField>,
      new_:Null<DBField>,
      droppingTable:Bool
    )
    :{ fields: Array<String>,
       fieldNames: Array<String>, // some fields are "virtual", they add multiple database fields. This is a list of all
       sql_before: Null<Array<String>>, // SQL required for setup (eg this creates triggers, sequences etc)
       sql_after: Null<Array<String>>,  // same but run after the step (this removes triggeres, sequences, eg after field change)
       sql_drop_fields: Array<String>,   // drop fields. This has to be ignored when the table is dropped.
       sql_create_fields: Array<String> // SQL adding fields to an (existing) table
     }
  {

    if (old == null){
      // create field

      var r = DBField.fieldCode(db_, tableName, new_, droppingTable);
      r.sql_remove = [];

      var createFields = new Array();
      for (o in r.fields)
        createFields.push("ALTER TABLE "+tableName+" ADD "+o);

      return {

        fields: r.fields,
        fieldNames: r.fieldNames,
        sql_before: r.sql_before, 
        sql_after: r.sql_after,
        sql_create_fields: createFields,
        sql_drop_fields: []

      }

    } else if (new_ == null) {
      // drop field
      
      var merged = DBFieldDecorator.merge(db_, old.type, tableName, old.name, old.__decorators, droppingTable);
      var r = DBField.fieldCode(db_, tableName, old, droppingTable);
      var res = new Array();
      var drop_fields;

      drop_fields = ["ALTER TABLE "+tableName+" DROP "+old.name];

      return {
        sql_after: merged.sql_remove,
        fields: [],
        fieldNames: r.fieldNames,
        sql_before: null,
        sql_drop_fields: drop_fields,
        sql_create_fields: []
      };

    } else {
      // change field
      if (old.name != new_.name)
        throw "not yet supported changing name of fields from "+old.name+" to "+new_.name;
      
      var old__code = DBField.fieldCode(db_,tableName, old, droppingTable);
      var new__code = DBField.fieldCode(db_,tableName, new_, droppingTable);

      var setup_differ = (old__code.sql_after != new__code.sql_after)
                      || (old__code.sql_before != new__code.sql_before);

      var changeFields = new Array<String>();
      if (old__code.fields.length == new__code.fields.length){
        for (i in 0 ... old__code.fields.length){
          var n = old__code.fieldNames[i];
          if (old__code.fields[i] != new__code.fields[i])
            changeFields.push("ALTER TABLE "+tableName+" "+new__code.alter[i]);
        }
      } else {
        // drop old
        for (o in old__code.fields)
          changeFields.push("ALTER TABLE "+tableName+" DROP "+o);
        // create new
        for (n in new__code.fields)
          changeFields.push("ALTER TABLE "+tableName+" ADD "+n);
      }

      return {
        sql_before: (setup_differ ? new__code.sql_before : [])
            .concat(changeFields),
        sql_after: setup_differ ? old__code.sql_remove.concat(new__code.sql_after) : [],
        fields: [],
        sql_drop_fields: [],
        fieldNames: [],
        sql_create_fields: []
      };
    }
      
  }
  
}

// represents a table
class DBTable implements IDBSerializable {

  public var primaryKeys: Array<String>;
  public var name:String;
  public var fields: Array<DBField>;
  public var __SPODClassName: String; // name of generated class
  public var __createSPODClass: Bool; // if true SPOD class file will be created or updated

  // TODO extend by keys etc
  public function new(name, primaryKeys: Array<String>, fields) {
    this.fields = fields;
    this.name = name;
    this.primaryKeys = primaryKeys;
    this.__SPODClassName = name;
    this.__createSPODClass = true;
  }

  public function createSPODClass (b:Bool){
    this.__createSPODClass = b;
    return this;
  }

  public function className(n:String){
    this.__SPODClassName=n;
    return this;
  }

  // property __autoinc {{{1
  public function autoincField():Null<DBField>{
    var list = DBHelper.concatArrays(fields.map(function(f){ return f.decoratorsOftype(DBFDAutoinc).length > 0 ? [f] : []; }));
    if (list.length > 1)
      throw "there cane be only one autoinc fiedl, found in table "+name+" : "+list.map(function(f){ return f.name; }).join(", ");
    else if (list.length == 1)
      return list[0];
    else
      return null;
  }
  // }}}

  // serialization {{{2
  // create object from serialized string
  public function toString() {
    return haxe.Serializer.run(this);
  }
  
  static function unserialize(s:String):DBField{
    // be careful if you change the items
    // Here is the place to implement backward compatibility !!
    return haxe.Unserializer.run(s);
  }
  // }}}
  
  // returns SQL queries which must be run to transform tabel old into table new
  static public function toSQL( db_: DBSupportedDatabaseType, old: Null<DBTable>, new_: Null<DBTable> ):Array<String> {
    var before = new List();
    var after = new List();
    var sqls = new List();

    var requests = new Array();
    var pushAll = function(pushCreateFields, r){
      if (r.sql_before != null)
        requests = requests.concat(r.sql_before);
      if (pushCreateFields)
        requests = requests.concat(r.sql_create_fields);
      requests = requests.concat(r.sql_drop_fields);
      if (r.sql_after != null)
        requests = requests.concat(r.sql_after);
    }
    var mysql_primary_included = function(x:DBTable){
      var autoInc = x.autoincField();

      if (autoInc != null) {
        if ( x.primaryKeys.length != 1 )
          throw "both declared: if autoinc is used the table must have one primary key!";

        if ( autoInc.name != x.primaryKeys[0])
          throw "both declared: autoinc field and differing primary key! This doesn't work for MySQL";
        return true;
      }
      return false;
    }

    var create_table = function(){
      var after = new Array();
      var before = new Array();

      var fields = new_.fields.map(function(f){
          var r = DBField.toSQL(db_, new_.name, null, f, false);
          if (r.sql_before != null)
            before = before.concat(r.sql_before);
          if (r.sql_after != null)
            after = after.concat(r.sql_after);
          return r.fields.join(",\n");
      }).join("\n,");

      var primary_key = (new_.primaryKeys.length > 0 ? ", PRIMARY KEY ("+ new_.primaryKeys.join(", ")+") \n" : "" );

      if (mysql_primary_included(new_))
        primary_key = ""; // primary key is set by DBFDAutoinc

      requests = requests.concat(before);
      requests.push(
        "CREATE TABLE "+new_.name+ "(\n"
        + fields +"\n"
        + primary_key
        +");\n");
      requests = requests.concat(after);
    }

    var drop_table = function(){
      requests.push( "DROP TABLE "+old.name+ ";" );
      // possible cleanups (remove enum types ?)
      for (f in old.fields){
        var r = DBField.toSQL(db_, old.name, f, null, true);
        if (r.sql_after != null)
          requests = requests.concat(r.sql_after);
      }
    }

    switch (db_){


      // Postgres case {{{2
      case db_postgres:
        
        if (old == null) {
          // create table
            //trace("creating sql for table "+new_.name);

          create_table();

        } else if (new_ == null) {
          // drop table
          drop_table();
            
        } else {
          // change table
          if (old.name != new_.name)
            throw "changing names not implemnted yet!";

          var changeSets = DBHelper.sep( old == null ? new Array() : old.fields
                        , new_ == null ? new Array() : new_.fields );

          if (old.primaryKeys != new_.primaryKeys){
            // drop primary key before column is dropped!
            if (old.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+old.name+" DROP CONSTRAINT "+old.name+"_pkey");
          }

          for (n in changeSets.n){ pushAll(true, DBField.toSQL(db_, new_.name, null, n, false)); }
          for (k in changeSets.k){ pushAll(false, DBField.toSQL(db_, new_.name, k.o, k.n, false)); }
          for (o in changeSets.o){ pushAll(false, DBField.toSQL(db_, new_.name, o, null, false)); }

          if (old.primaryKeys != new_.primaryKeys){
            if (new_.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+new_.name+" ADD PRIMARY KEY ("+new_.primaryKeys.join(", ")+")");
          }

        }

      // MySQL case {{{2
      case db_mysql:

        if (old == null){
          // create table
          create_table();


        } else if (new_ == null){
          // drop table
          drop_table();

        } else {
          // change table

          if (old.name != new_.name)
            throw "changing names not implemnted yet!";

          var changeSets = DBHelper.sep( old == null ? new Array() : old.fields
                        , new_ == null ? new Array() : new_.fields );

          for (n in changeSets.n){ pushAll(true, DBField.toSQL(db_, new_.name, null, n, false)); }
          for (k in changeSets.k){ pushAll(false, DBField.toSQL(db_, new_.name, k.o, k.n, false)); }
          for (o in changeSets.o){ pushAll(false, DBField.toSQL(db_, new_.name, o, null, false)); }

          if (old.primaryKeys != new_.primaryKeys){
            trace("A");
            if (old.primaryKeys.length > 0 && !mysql_primary_included(old))
              requests.push("ALTER TABLE "+old.name+" DROP KEY "+old.name+"_pkey");

            trace("B");
            if (new_.primaryKeys.length > 0 && !mysql_primary_included(new_))
              requests.push("ALTER TABLE "+new_.name+" ADD PRIMARY KEY ("+new_.primaryKeys.join(", ")+")");
          }

        }
    } // }}}

    return requests;
  }

}
