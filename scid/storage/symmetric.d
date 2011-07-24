module scid.storage.symmetric;

import scid.internal.assertmessages;
import scid.bindings.blas.dblas;
import scid.storage.cowarray;
import scid.storage.packedmat;
import scid.matrix, scid.vector;
import scid.common.traits;
import std.math, std.algorithm;
import std.complex;

template SymmetricStorage( ElementOrArray, MatrixTriangle triangle = MatrixTriangle.Upper, StorageOrder storageOrder = StorageOrder.ColumnMajor )
	if( isFortranType!(BaseElementType!ElementOrArray) ) {
	
	static if( isFortranType!ElementOrArray )
		alias PackedStorage!( SymmetricArrayAdapter!(CowArrayRef!ElementOrArray, triangle, storageOrder) ) SymmetricStorage;
	else
		alias PackedStorage!( SymmetricArrayAdapter!(ElementOrArray, triangle, storageOrder) )             SymmetricStorage;
}

struct SymmetricArrayAdapter( ContainerRef_, MatrixTriangle tri_, StorageOrder storageOrder_ ) {
	alias ContainerRef_                ContainerRef;
	alias BaseElementType!ContainerRef ElementType;
	
	alias SymmetricArrayAdapter!(
		ContainerRef,
		tri_ == MatrixTriangle.Upper ? MatrixTriangle.Lower : MatrixTriangle.Upper,
		storageOrder_ 
	) Transposed;
	
	enum triangle     = tri_;
	enum storageOrder = storageOrder_;
	enum isRowMajor   = storageOrder == StorageOrder.RowMajor;
	enum isUpper      = triangle     == MatrixTriangle.Upper;
	
	/** Is the matrix hermitian? */
	enum isHermitian = isComplex!ElementType;
	
	static if( isHermitian )
		enum storageType  = MatrixStorageType.Hermitian;
	else
		enum storageType  = MatrixStorageType.Symmetric;
	
	this( size_t newSize ) {
		size_  = newSize;
		array_ = ContainerRef( newSize * (newSize + 1) / 2 );
	}
	
	this( size_t newSize, void* ) {
		size_  = newSize;
		array_ = ContainerRef( newSize * (newSize + 1) / 2, null );
	}
	
	this( ElementType[] initializer ) {
		auto tri  = (sqrt( initializer.length * 8.0 + 1.0 ) - 1.0 ) / 2.0;
		
		assert( tri - cast(int) tri <= 0, msgPrefix_ ~ "Initializer list is not triangular." );
		
		size_  = cast(size_t) tri;
		array_ = ContainerRef( initializer );
	}
	
	this( typeof(this) *other ) {
		array_ = ContainerRef( other.array_.ptr );
		size_  = other.size_;
	}
	
	void resize( size_t size ) {
		array_ = ContainerRef( size*(size+1)/2, null );
		size_  = size;
	}
	
	ref typeof( this ) opAssign( typeof(this) rhs ) {
		move( rhs.array_, array_ );
		size_  = rhs.size_;
		return this;
	}

	static if( isHermitian ) {
		/** Generic conjugate - works on both cdouble & Complex!double. */
		static const (C) genConj( C )( C z ) {
			static if( __traits( compiles, z.conj ) )
				return z.conj;
			else
				return conj(z);
		}
	}

	ElementType index( size_t row, size_t column ) const
	in {
		assert( row < size_ );
		assert( column < size_ );
	} body {
		if( needSwap_( row, column ) ) {
			static if( isHermitian ) {
				return genConj( array_.index( map_( column, row ) ) );
			} else {
				return array_.index( map_( column, row ) );
			}
		} else {
			return array_.index( map_( row, column ) );
		}
	}	

	void indexAssign(string op="")( ElementType rhs, size_t row, size_t column )
	in {
		assert( row < size_ );
		assert( column < size_ );
	} body {
		if( needSwap_( row, column ) ) {
			static if( isHermitian ) {
				array_.indexAssign!op( genConj(rhs), map_( column, row ) );
			} else {
				array_.indexAssign!op( rhs, map_( column, row ) );
			}
		} else {
			array_.indexAssign!op( rhs, map_( row, column ) );
		}
	}
	
	@property {
		typeof(this)*       ptr()         { return &this; }
		ElementType*        data()        { return array_.data; }
		const(ElementType)* cdata() const { return array_.cdata; }
		size_t              size()  const { return size_; }
	}
	
	alias size rows;
	alias size columns;
	alias size major;
	alias size minor;
	
private:
	mixin MatrixErrorMessages;

	size_t mapHelper_( bool colUpper )( size_t i, size_t j ) const {
		static if( colUpper ) return i + j * (j + 1) / 2;
		else                  return i + ( ( size_ + size_ - j - 1 ) * j ) / 2;
	}

	size_t map_( size_t i, size_t j ) const {
		static if( isRowMajor )
			return mapHelper_!( !isUpper )( j, i );
		else
			return mapHelper_!( isUpper )( i, j );
	}

	bool needSwap_( size_t i, size_t j ) const {
		static if( isUpper ) {
			return i > j;
		} else {
			return i < j;
		}
	}
	
	size_t   size_;
	ContainerRef array_;
}